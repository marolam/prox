import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:http/http.dart" as http;
import "dart:convert";

import "package:prox/services/points_service.dart";

/// Firestore-backed monetization state.
///
/// This keeps entitlements server-backed (cross-device) and powers points-based
/// purchases so monetization buttons perform real state transitions.
class MonetizationService {
  MonetizationService._();
  static final MonetizationService instance = MonetizationService._();

  static const int monthlySubscriptionPoints = 200;
  static const double monthlySubscriptionUsd = 49.99;
  static const int oneTimeUnlockPoints = 1200;
  static const int referralRewardPoints = 5;
  static const int supportRewardPoints = 1;
  static const String paymentModePointsOnly = "points_only";
  static const String paymentModeCashOnly = "cash_only";
  static const String paymentModePointsFirst = "points_first";
  static const String _externalCheckoutSessionUrl = String.fromEnvironment(
    "PROX_EXTERNAL_CHECKOUT_SESSION_URL",
    defaultValue: "",
  );

  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  double get usdPerPoint => monthlySubscriptionUsd / monthlySubscriptionPoints;

  double usdRemainderForPoints(int pointsApplied) {
    final int bounded = pointsApplied.clamp(0, monthlySubscriptionPoints);
    final int remaining = monthlySubscriptionPoints - bounded;
    return remaining * usdPerPoint;
  }

  int pointsMissingForZeroUsd(int pointsApplied) {
    final int bounded = pointsApplied.clamp(0, monthlySubscriptionPoints);
    return monthlySubscriptionPoints - bounded;
  }

  int referralsNeededForPointsGap(int pointsGap) {
    final int gap = pointsGap <= 0 ? 0 : pointsGap;
    return gap == 0 ? 0 : ((gap + referralRewardPoints - 1) ~/ referralRewardPoints);
  }

  int supportTicketsNeededForPointsGap(int pointsGap) {
    final int gap = pointsGap <= 0 ? 0 : pointsGap;
    return gap == 0 ? 0 : ((gap + supportRewardPoints - 1) ~/ supportRewardPoints);
  }

  DocumentReference<Map<String, dynamic>> _savedPaymentMethodRef(String uid) {
    return _fs
        .collection("users")
        .doc(uid)
        .collection("billing")
        .doc("paymentMethods")
        .collection("items")
        .doc("default");
  }

        CollectionReference<Map<String, dynamic>> _paymentMethodsCollectionRef(String uid) {
          return _fs
          .collection("users")
          .doc(uid)
          .collection("billing")
          .doc("paymentMethods")
          .collection("items");
        }

        DocumentReference<Map<String, dynamic>> _billingPreferencesRef(String uid) {
          return _fs
          .collection("users")
          .doc(uid)
          .collection("billing")
          .doc("preferences");
        }

  Future<void> saveDefaultPaymentMethod({
    required String uid,
    required String paymentMethodId,
    String? brand,
    String? last4,
    String provider = "stripe_stub",
  }) async {
    final cleanUid = uid.trim();
    final cleanPm = paymentMethodId.trim();
    if (cleanUid.isEmpty || cleanPm.isEmpty) {
      throw StateError("uid and paymentMethodId are required");
    }

    final cardPayload = <String, Object?>{
      "paymentMethodId": cleanPm,
      "brand": (brand ?? "").trim(),
      "last4": (last4 ?? "").trim(),
      "provider": provider.trim().isEmpty ? "stripe_stub" : provider.trim(),
      "active": true,
      "isDefault": true,
      "updatedAt": FieldValue.serverTimestamp(),
    };

    await _paymentMethodsCollectionRef(cleanUid)
        .doc(cleanPm)
        .set(cardPayload, SetOptions(merge: true));

    await _savedPaymentMethodRef(cleanUid).set(<String, Object?>{
      "paymentMethodId": cleanPm,
      "brand": (brand ?? "").trim(),
      "last4": (last4 ?? "").trim(),
      "provider": provider.trim().isEmpty ? "stripe_stub" : provider.trim(),
      "active": true,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setDefaultPaymentMethodId({
    required String uid,
    required String paymentMethodId,
  }) async {
    final cleanUid = uid.trim();
    final cleanPm = paymentMethodId.trim();
    if (cleanUid.isEmpty || cleanPm.isEmpty) {
      throw StateError("uid and paymentMethodId are required");
    }

    final cardSnap = await _paymentMethodsCollectionRef(cleanUid).doc(cleanPm).get();
    final card = cardSnap.data() ?? <String, dynamic>{
      "paymentMethodId": cleanPm,
      "brand": "",
      "last4": "",
      "provider": "square",
      "active": true,
    };

    final batch = _fs.batch();
    final allCards = await _paymentMethodsCollectionRef(cleanUid).where("active", isEqualTo: true).get();
    for (final doc in allCards.docs) {
      batch.set(doc.reference, <String, Object?>{
        "isDefault": doc.id == cleanPm,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    batch.set(_savedPaymentMethodRef(cleanUid), <String, Object?>{
      "paymentMethodId": cleanPm,
      "brand": (card["brand"] ?? "").toString().trim(),
      "last4": (card["last4"] ?? "").toString().trim(),
      "provider": (card["provider"] ?? "square").toString().trim(),
      "active": true,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<List<Map<String, String>>> listPaymentMethods({
    required String uid,
  }) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return const <Map<String, String>>[];

    final snap = await _paymentMethodsCollectionRef(cleanUid)
        .where("active", isEqualTo: true)
        .get();

    return _mapPaymentMethods(snap);
  }

  Future<List<Map<String, String>>> listPaymentMethodsCached({
    required String uid,
  }) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return const <Map<String, String>>[];

    try {
      final snap = await _paymentMethodsCollectionRef(cleanUid)
          .where("active", isEqualTo: true)
          .get(const GetOptions(source: Source.cache));
      return _mapPaymentMethods(snap);
    } catch (_) {
      return const <Map<String, String>>[];
    }
  }

  List<Map<String, String>> _mapPaymentMethods(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {

    final out = <Map<String, String>>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      final pm = (d["paymentMethodId"] ?? doc.id).toString().trim();
      if (pm.isEmpty) continue;
      out.add(<String, String>{
        "paymentMethodId": pm,
        "brand": (d["brand"] ?? "").toString().trim(),
        "last4": (d["last4"] ?? "").toString().trim(),
        "provider": (d["provider"] ?? "square").toString().trim(),
        "isDefault": (d["isDefault"] == true).toString(),
      });
    }

    out.sort((a, b) {
      final aDef = a["isDefault"] == "true";
      final bDef = b["isDefault"] == "true";
      if (aDef == bDef) return 0;
      return aDef ? -1 : 1;
    });

    return out;
  }

  Future<void> removePaymentMethod({
    required String uid,
    required String paymentMethodId,
  }) async {
    final cleanUid = uid.trim();
    final cleanPm = paymentMethodId.trim();
    if (cleanUid.isEmpty || cleanPm.isEmpty) {
      throw StateError("uid and paymentMethodId are required");
    }

    final paymentMethodsRef = _paymentMethodsCollectionRef(cleanUid);
    final cardRef = paymentMethodsRef.doc(cleanPm);
    final defaultRef = _savedPaymentMethodRef(cleanUid);

    final cardSnap = await cardRef.get();
    final removedCard = cardSnap.data() ?? const <String, dynamic>{};

    final activeSnap = await paymentMethodsRef.where("active", isEqualTo: true).get();
    QueryDocumentSnapshot<Map<String, dynamic>>? nextDefaultDoc;
    for (final doc in activeSnap.docs) {
      final id = (doc.data()["paymentMethodId"] ?? doc.id).toString().trim();
      if (id.isNotEmpty && id != cleanPm) {
        nextDefaultDoc = doc;
        break;
      }
    }

    final hasNextDefault = nextDefaultDoc != null;
    final nextDefaultDocId = nextDefaultDoc?.id ?? "";
    final batch = _fs.batch();

    batch.set(cardRef, <String, Object?>{
      "active": false,
      "isDefault": false,
      "updatedAt": FieldValue.serverTimestamp(),
      "removedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    for (final doc in activeSnap.docs) {
      if (doc.id == cardRef.id) continue;
      batch.set(doc.reference, <String, Object?>{
        "isDefault": hasNextDefault && doc.id == nextDefaultDocId,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (!hasNextDefault) {
      batch.set(defaultRef, <String, Object?>{
        "paymentMethodId": "",
        "brand": "",
        "last4": "",
        "provider": (removedCard["provider"] ?? "square").toString().trim(),
        "active": false,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      final nextDoc = nextDefaultDoc;
      final next = nextDoc.data();
      final nextPmId = (next["paymentMethodId"] ?? nextDoc.id).toString().trim();
      batch.set(defaultRef, <String, Object?>{
        "paymentMethodId": nextPmId,
        "brand": (next["brand"] ?? "").toString().trim(),
        "last4": (next["last4"] ?? "").toString().trim(),
        "provider": (next["provider"] ?? "square").toString().trim(),
        "active": true,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Future<Map<String, dynamic>> getBillingPreferences({required String uid}) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) {
      return <String, dynamic>{
        "autoRenewWithSelectedCard": false,
        "paymentMode": paymentModePointsFirst,
      };
    }

    final snap = await _billingPreferencesRef(cleanUid).get();
    final d = snap.data() ?? const <String, dynamic>{};
    final mode = (d["paymentMode"] ?? paymentModePointsFirst).toString().trim();
    final validMode =
        mode == paymentModePointsOnly || mode == paymentModeCashOnly || mode == paymentModePointsFirst;

    return <String, dynamic>{
      "autoRenewWithSelectedCard": d["autoRenewWithSelectedCard"] == true,
      "paymentMode": validMode ? mode : paymentModePointsFirst,
    };
  }

  Future<void> saveBillingPreferences({
    required String uid,
    required bool autoRenewWithSelectedCard,
    required String paymentMode,
  }) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return;

    final cleanMode = paymentMode.trim();
    final effectiveMode =
        cleanMode == paymentModePointsOnly || cleanMode == paymentModeCashOnly || cleanMode == paymentModePointsFirst
            ? cleanMode
            : paymentModePointsFirst;

    await _billingPreferencesRef(cleanUid).set(<String, Object?>{
      "autoRenewWithSelectedCard": autoRenewWithSelectedCard,
      "paymentMode": effectiveMode,
      "preferPointsFirst": effectiveMode == paymentModePointsFirst,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, String>> getDefaultPaymentMethod({
    required String uid,
  }) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return const <String, String>{};

    final snap = await _savedPaymentMethodRef(cleanUid).get();
    if (!snap.exists) return const <String, String>{};
    final d = snap.data() ?? const <String, dynamic>{};

    final paymentMethodId = (d["paymentMethodId"] ?? "").toString().trim();
    if (paymentMethodId.isEmpty) return const <String, String>{};

    return <String, String>{
      "paymentMethodId": paymentMethodId,
      "brand": (d["brand"] ?? "").toString(),
      "last4": (d["last4"] ?? "").toString(),
      "provider": (d["provider"] ?? "stripe_stub").toString(),
    };
  }

  Future<Map<String, String>> createExternalCheckoutSession({
    required String uid,
    required String sku,
    String provider = "square",
    String? paymentMethodId,
  }) async {
    final cleanUid = uid.trim();
    final cleanSku = sku.trim();
    if (cleanUid.isEmpty || cleanSku.isEmpty) {
      throw StateError("uid and sku are required");
    }

    final endpoint = _externalCheckoutSessionUrl.trim();
    if (endpoint.isEmpty) {
      // Fallback so testers can still validate flow when endpoint is not configured.
      final localSessionId = await createExternalCheckoutIntent(
        uid: cleanUid,
        sku: cleanSku,
        provider: provider,
      );
      return <String, String>{
        "sessionId": localSessionId,
        "checkoutUrl": "",
      };
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid != cleanUid) {
      throw StateError("Authenticated user mismatch");
    }

    final idToken = await currentUser.getIdToken(true);
    final response = await http.post(
      Uri.parse(endpoint),
      headers: <String, String>{
        "content-type": "application/json",
        "authorization": "Bearer $idToken",
      },
      body: jsonEncode(<String, String>{
        "sku": cleanSku,
        "provider": provider.trim().isEmpty ? "square" : provider.trim(),
        if (paymentMethodId != null && paymentMethodId.trim().isNotEmpty)
          "paymentMethodId": paymentMethodId.trim(),
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        "External checkout session failed (${response.statusCode}): ${response.body}",
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final sessionId = (data["sessionId"] ?? "").toString();
    final checkoutUrl = (data["checkoutUrl"] ?? "").toString();
    if (sessionId.trim().isEmpty) {
      throw StateError("External checkout response missing sessionId");
    }

    return <String, String>{
      "sessionId": sessionId,
      "checkoutUrl": checkoutUrl,
    };
  }

  Future<Map<String, dynamic>> getExternalCheckoutSession({
    required String uid,
    required String sessionId,
  }) async {
    final cleanUid = uid.trim();
    final cleanSessionId = sessionId.trim();
    if (cleanUid.isEmpty || cleanSessionId.isEmpty) {
      throw StateError("uid and sessionId are required");
    }

    final ref = _fs
        .collection("users")
        .doc(cleanUid)
        .collection("billing")
        .doc("externalCheckout")
        .collection("items")
        .doc(cleanSessionId);

    final snap = await ref.get();
    if (!snap.exists) {
      return <String, dynamic>{
        "exists": false,
        "status": "",
      };
    }

    final data = snap.data() ?? const <String, dynamic>{};
    return <String, dynamic>{
      "exists": true,
      "status": (data["status"] ?? "").toString().trim().toLowerCase(),
      "sku": (data["sku"] ?? "").toString().trim(),
      "provider": (data["provider"] ?? "").toString().trim(),
      "providerReference": (data["providerReference"] ?? "").toString().trim(),
    };
  }

  DocumentReference<Map<String, dynamic>> _entitlementRef(String uid) {
    return _fs
        .collection("users")
        .doc(uid)
        .collection("billing")
        .doc("entitlements");
  }

  DocumentReference<Map<String, dynamic>> _invoiceRef(
      String uid, String invoiceId) {
    return _fs
        .collection("users")
        .doc(uid)
        .collection("billing")
        .doc("invoices")
        .collection("items")
        .doc(invoiceId);
  }

  Future<bool> isBusinessPurchased(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return false;
    final snap = await _entitlementRef(clean).get();
    return snap.data()?['businessPurchased'] == true;
  }

  Future<bool> isBusinessSubscriptionActive(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return false;

    final snap = await _entitlementRef(clean).get();
    if (!snap.exists) return false;

    final data = snap.data() ?? <String, dynamic>{};
    if (data['businessSubscriptionActive'] != true) return false;

    final rawRenew = data['subscriptionRenewsAt'];
    if (rawRenew is Timestamp) {
      return rawRenew.toDate().isAfter(DateTime.now());
    }
    return true;
  }

  /// In our UX, "Business unlocked" means:
  /// - either a one-time purchase has been recorded, OR
  /// - a subscription is active.
  Future<bool> isBusinessUnlocked(String uid) async {
    final purchased = await isBusinessPurchased(uid);
    if (purchased) return true;
    return isBusinessSubscriptionActive(uid);
  }

  Future<bool> isHighRadiusUnlocked(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return false;
    final snap = await _entitlementRef(clean).get();
    return snap.data()?['highRadiusUnlocked'] == true;
  }

  Future<bool> getEntitlementBool({
    required String uid,
    required String key,
  }) async {
    final cleanUid = uid.trim();
    final cleanKey = key.trim();
    if (cleanUid.isEmpty || cleanKey.isEmpty) return false;

    final snap = await _entitlementRef(cleanUid).get();
    return snap.data()?[cleanKey] == true;
  }

  Future<bool> isBusinessStoreUnlocked(String uid) {
    return getEntitlementBool(uid: uid, key: "businessStoreUnlocked");
  }

  Future<bool> isBusinessWalletUnlocked(String uid) {
    return getEntitlementBool(uid: uid, key: "businessWalletUnlocked");
  }

  Future<Map<String, dynamic>> getEntitlementsMap({required String uid}) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return const <String, dynamic>{};

    final snap = await _entitlementRef(cleanUid).get();
    return snap.data() ?? const <String, dynamic>{};
  }

  Future<void> setBusinessPurchased({
    required String uid,
    required bool purchased,
    String? sku,
  }) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;

    final Map<String, Object?> payload = <String, Object?>{
      'businessPurchased': purchased,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (sku != null && sku.trim().isNotEmpty) {
      payload['lastSku'] = sku.trim();
    }

    await _entitlementRef(clean).set(payload, SetOptions(merge: true));
  }

  Future<void> setHighRadiusUnlocked({
    required String uid,
    required bool unlocked,
    String? sku,
  }) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;

    final Map<String, Object?> payload = <String, Object?>{
      'highRadiusUnlocked': unlocked,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (sku != null && sku.trim().isNotEmpty) {
      payload['lastSku'] = sku.trim();
    }

    await _entitlementRef(clean).set(payload, SetOptions(merge: true));
  }

  Future<void> setEntitlementBool({
    required String uid,
    required String key,
    required bool value,
    String? sku,
  }) async {
    final cleanUid = uid.trim();
    final cleanKey = key.trim();
    if (cleanUid.isEmpty || cleanKey.isEmpty) return;

    final payload = <String, Object?>{
      cleanKey: value,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (sku != null && sku.trim().isNotEmpty) {
      payload['lastSku'] = sku.trim();
    }

    await _entitlementRef(cleanUid).set(payload, SetOptions(merge: true));
  }

  Future<void> setBusinessSubscriptionActive({
    required String uid,
    required bool active,
    String? sku,
  }) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;

    final Map<String, Object?> payload = <String, Object?>{
      'businessSubscriptionActive': active,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (active) {
      payload['subscriptionStartedAt'] = FieldValue.serverTimestamp();
      payload['subscriptionRenewsAt'] = Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 30)),
      );
    } else {
      payload['subscriptionRenewsAt'] = null;
    }

    if (sku != null && sku.trim().isNotEmpty) {
      payload['lastSku'] = sku.trim();
    }

    await _entitlementRef(clean).set(payload, SetOptions(merge: true));
  }

  Future<void> setBusinessActivationBundleUnlocked({
    required String uid,
    required bool unlocked,
    String? sku,
  }) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;

    final payload = <String, Object?>{
      "businessStoreUnlocked": unlocked,
      "businessWalletUnlocked": unlocked,
      "updatedAt": FieldValue.serverTimestamp(),
    };
    if (sku != null && sku.trim().isNotEmpty) {
      payload["lastSku"] = sku.trim();
    }

    await _entitlementRef(clean).set(payload, SetOptions(merge: true));
  }

  Future<String?> getLastSku(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return null;

    final snap = await _entitlementRef(clean).get();
    final v = snap.data()?['lastSku']?.toString();
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }

  Future<bool> purchaseOneTimeUnlockWithPoints(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return false;

    final ok = await PointsService.instance.spendPoints(
      uid: clean,
      amount: oneTimeUnlockPoints,
      reason: 'Business one-time unlock',
      category: 'billing',
      contextType: 'business_one_time_unlock',
    );
    if (!ok) return false;

    await setBusinessPurchased(
        uid: clean, purchased: true, sku: 'biz_onetime_unlock');
    await setBusinessActivationBundleUnlocked(
      uid: clean,
      unlocked: true,
      sku: 'biz_onetime_unlock',
    );
    await _logInvoice(
      uid: clean,
      sku: 'biz_onetime_unlock',
      amountPoints: oneTimeUnlockPoints,
      status: 'paid',
      paymentMethod: 'points',
      description: 'Business Mode one-time unlock',
    );
    return true;
  }

  Future<bool> startMonthlySubscriptionWithPoints(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return false;

    final ok = await PointsService.instance.spendPoints(
      uid: clean,
      amount: monthlySubscriptionPoints,
      reason: 'Business monthly subscription',
      category: 'billing',
      contextType: 'business_monthly_subscription',
    );
    if (!ok) return false;

    await setBusinessSubscriptionActive(
      uid: clean,
      active: true,
      sku: 'biz_monthly_subscription',
    );
    await setBusinessActivationBundleUnlocked(
      uid: clean,
      unlocked: true,
      sku: 'biz_monthly_subscription',
    );
    await _logInvoice(
      uid: clean,
      sku: 'biz_monthly_subscription',
      amountPoints: monthlySubscriptionPoints,
      status: 'paid',
      paymentMethod: 'points',
      description: 'Business monthly subscription',
    );
    return true;
  }

  Future<void> cancelMonthlySubscription(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;

    await setBusinessSubscriptionActive(
      uid: clean,
      active: false,
      sku: 'biz_monthly_subscription',
    );

    await _entitlementRef(clean).set(
      <String, Object?>{
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _logInvoice({
    required String uid,
    required String sku,
    required int amountPoints,
    required String status,
    required String paymentMethod,
    required String description,
  }) async {
    final invoiceId = _fs.collection('tmp').doc().id;
    await _invoiceRef(uid, invoiceId).set(<String, Object?>{
      'invoiceId': invoiceId,
      'sku': sku,
      'amountPoints': amountPoints,
      'status': status,
      'paymentMethod': paymentMethod,
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> createExternalCheckoutIntent({
    required String uid,
    required String sku,
    String provider = "stripe_stub",
  }) async {
    final cleanUid = uid.trim();
    final cleanSku = sku.trim();
    if (cleanUid.isEmpty || cleanSku.isEmpty) {
      throw StateError("uid and sku are required");
    }

    final ref = _fs
        .collection("users")
        .doc(cleanUid)
        .collection("billing")
        .doc("externalCheckout")
        .collection("items")
        .doc();

    await ref.set(<String, Object?>{
      "sessionId": ref.id,
      "uid": cleanUid,
      "sku": cleanSku,
      "provider": provider.trim().isEmpty ? "stripe_stub" : provider.trim(),
      "status": "intent_created",
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return ref.id;
  }

  /// Reset all local monetization flags for this user.
  /// Dev/testing only.
  Future<void> resetForUser(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;

    await _entitlementRef(clean).set(
      <String, Object?>{
        'businessPurchased': false,
        'businessSubscriptionActive': false,
        'businessStoreUnlocked': false,
        'businessWalletUnlocked': false,
        'highRadiusUnlocked': false,
        'lastSku': null,
        'subscriptionRenewsAt': null,
        'subscriptionStartedAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
