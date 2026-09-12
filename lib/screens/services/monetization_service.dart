import "package:prox/services/business_mode/business_access_policy.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:http/http.dart" as http;
import "dart:convert";

import "package:prox/services/points_service.dart";
import "package:cloud_functions/cloud_functions.dart";
import "package:shared_preferences/shared_preferences.dart";

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
    return gap == 0
        ? 0
        : ((gap + referralRewardPoints - 1) ~/ referralRewardPoints);
  }

  int supportTicketsNeededForPointsGap(int pointsGap) {
    final int gap = pointsGap <= 0 ? 0 : pointsGap;
    return gap == 0
        ? 0
        : ((gap + supportRewardPoints - 1) ~/ supportRewardPoints);
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

  CollectionReference<Map<String, dynamic>> _paymentMethodsCollectionRef(
    String uid,
  ) {
    return _fs
        .collection("users")
        .doc(uid)
        .collection("billing")
        .doc("paymentMethods")
        .collection("items");
  }

  Future<void> saveDefaultPaymentMethod({
    required String uid,
    required String paymentMethodId,
    String? brand,
    String? last4,
    String provider = "square",
  }) async {
    throw StateError(
      "Manage payment details in the secure payment provider checkout.",
    );
  }

  Future<void> setDefaultPaymentMethodId({
    required String uid,
    required String paymentMethodId,
  }) async {
    throw StateError(
      "Manage payment details in the secure payment provider checkout.",
    );
  }

  Future<List<Map<String, String>>> listPaymentMethods({
    required String uid,
  }) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return const <Map<String, String>>[];

    final snap = await _paymentMethodsCollectionRef(
      cleanUid,
    ).where("active", isEqualTo: true).get();

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
    throw StateError(
      "Manage payment details in the secure payment provider checkout.",
    );
  }

  Future<Map<String, dynamic>> getBillingPreferences({
    required String uid,
  }) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) {
      return <String, dynamic>{
        "autoRenewWithSelectedCard": false,
        "paymentMode": paymentModePointsFirst,
      };
    }

    final prefs = await SharedPreferences.getInstance();
    final mode =
        prefs.getString("billing_payment_mode:$cleanUid") ??
        paymentModePointsFirst;
    final validMode =
        mode == paymentModePointsOnly ||
        mode == paymentModeCashOnly ||
        mode == paymentModePointsFirst;

    return <String, dynamic>{
      "autoRenewWithSelectedCard": false,
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
        cleanMode == paymentModePointsOnly ||
            cleanMode == paymentModeCashOnly ||
            cleanMode == paymentModePointsFirst
        ? cleanMode
        : paymentModePointsFirst;

    if (autoRenewWithSelectedCard)
      throw StateError("Access is prepaid and does not renew automatically.");
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("billing_payment_mode:$cleanUid", effectiveMode);
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
      "provider": (d["provider"] ?? "square").toString(),
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
    final endpointUri = Uri.tryParse(endpoint);
    if (endpointUri == null ||
        endpointUri.scheme != "https" ||
        endpointUri.host.isEmpty ||
        endpointUri.userInfo.isNotEmpty) {
      throw StateError(
        "Card checkout is not available in this build. No payment has been taken.",
      );
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid != cleanUid) {
      throw StateError("Authenticated user mismatch");
    }

    final idToken = await currentUser.getIdToken(true);
    final response = await http
        .post(
          endpointUri,
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
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        "Card checkout is unavailable (${response.statusCode}). Please try again.",
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final sessionId = (data["sessionId"] ?? "").toString();
    final checkoutUrl = (data["checkoutUrl"] ?? "").toString();
    final checkoutUri = Uri.tryParse(checkoutUrl);
    if (sessionId.trim().isEmpty ||
        checkoutUri == null ||
        checkoutUri.scheme != "https" ||
        checkoutUri.host.isEmpty ||
        checkoutUri.userInfo.isNotEmpty) {
      throw StateError(
        "The payment provider did not return a secure checkout page.",
      );
    }

    return <String, String>{"sessionId": sessionId, "checkoutUrl": checkoutUrl};
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
      return <String, dynamic>{"exists": false, "status": ""};
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

    return BusinessAccessPolicy.hasActivePrepaid(data);
  }

  /// Access is a confirmed lifetime purchase or prepaid time with a valid expiry.
  Future<bool> isBusinessUnlocked(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty || _auth.currentUser?.uid != clean) return false;
    final snap = await _entitlementRef(
      clean,
    ).get().timeout(const Duration(seconds: 8));
    if (_auth.currentUser?.uid != clean) return false;
    return BusinessAccessPolicy.hasAccess(snap.data() ?? <String, dynamic>{});
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
  }) async => _serverOnly();
  Future<void> setHighRadiusUnlocked({
    required String uid,
    required bool unlocked,
    String? sku,
  }) async => _serverOnly();
  Future<void> setEntitlementBool({
    required String uid,
    required String key,
    required bool value,
    String? sku,
  }) async => _serverOnly();
  Future<void> setBusinessSubscriptionActive({
    required String uid,
    required bool active,
    String? sku,
  }) async => _serverOnly();
  Future<void> setBusinessActivationBundleUnlocked({
    required String uid,
    required bool unlocked,
    String? sku,
  }) async => _serverOnly();
  Never _serverOnly() =>
      throw StateError("Access is granted by Prox after a verified purchase.");

  Future<String?> getLastSku(String uid) async =>
      (await _entitlementRef(uid).get()).data()?["lastSku"]?.toString();

  final Map<String, Future<bool>> _purchases = {};
  Future<bool> _purchaseWithPoints(String uid, String sku) {
    final key = "$uid:$sku";
    final pending = _purchases[key];
    if (pending != null) return pending;
    final future = _submitPointsPurchase(uid, sku);
    _purchases[key] = future;
    return future.whenComplete(() {
      if (identical(_purchases[key], future)) _purchases.remove(key);
    });
  }

  Future<bool> _submitPointsPurchase(String uid, String sku) async {
    if (_auth.currentUser?.uid != uid) throw StateError("Sign in to purchase.");
    final prefs = await SharedPreferences.getInstance();
    final key = "pending_purchase:$uid:$sku";
    final requestId =
        prefs.getString(key) ?? _fs.collection("purchaseIds").doc().id;
    await prefs.setString(key, requestId);
    try {
      final result = await FirebaseFunctions.instanceFor(region: "us-central1")
          .httpsCallable(
            "purchaseWithPoints",
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
          )
          .call<dynamic>({"sku": sku, "requestId": requestId});
      final data = result.data;
      if (data is! Map || data["purchased"] != true)
        throw StateError("Purchase was not confirmed.");
      await prefs.remove(key);
      try {
        await PointsService.instance.refreshMeta(uid);
      } catch (_) {}
      return true;
    } on FirebaseFunctionsException catch (error) {
      if (error.code == "failed-precondition" &&
          (error.message ?? "").toLowerCase().contains("not enough points")) {
        await prefs.remove(key);
        return false;
      }
      rethrow;
    }
  }

  Future<bool> purchaseOneTimeUnlockWithPoints(String uid) =>
      _purchaseWithPoints(uid, "biz_onetime_unlock");
  Future<bool> startMonthlySubscriptionWithPoints(String uid) =>
      _purchaseWithPoints(uid, "biz_monthly_subscription");

  Future<void> cancelMonthlySubscription(String uid) async {
    if (_auth.currentUser?.uid != uid)
      throw StateError("Sign in to manage your access.");
    await FirebaseFunctions.instanceFor(
      region: "us-central1",
    ).httpsCallable("cancelMySubscription").call<dynamic>();
  }

  Future<String> createExternalCheckoutIntent({
    required String uid,
    required String sku,
    String provider = "square",
  }) async {
    final session = await createExternalCheckoutSession(
      uid: uid,
      sku: sku,
      provider: provider,
    );
    return session["sessionId"]!;
  }

  Future<void> resetForUser(String uid) async => _serverOnly();
}
