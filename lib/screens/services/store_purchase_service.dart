import "package:cloud_firestore/cloud_firestore.dart";

import "package:firebase_auth/firebase_auth.dart";
import "package:cloud_functions/cloud_functions.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:prox/services/points_service.dart";

class StoreItemDefinition {
  final String sku;
  final int costPoints;
  final bool requiresBusiness;

  const StoreItemDefinition({
    required this.sku,
    required this.costPoints,
    required this.requiresBusiness,
  });
}

enum StorePurchaseStatus {
  purchased,
  alreadyOwned,
  locked,
  insufficientPoints,
  unknownSku,
}

class StorePurchaseResult {
  final StorePurchaseStatus status;
  final int pointsSpent;

  const StorePurchaseResult(this.status, {this.pointsSpent = 0});
}

class StorePurchaseService {
  StorePurchaseService._();
  static final StorePurchaseService instance = StorePurchaseService._();

  static const Map<String, StoreItemDefinition> _catalog =
      <String, StoreItemDefinition>{
    "cosmetic_profile_glow": StoreItemDefinition(
      sku: "cosmetic_profile_glow",
      costPoints: 15,
      requiresBusiness: false,
    ),
    "cosmetic_beacon_palette": StoreItemDefinition(
      sku: "cosmetic_beacon_palette",
      costPoints: 25,
      requiresBusiness: false,
    ),
    "cosmetic_chat_bubble_themes": StoreItemDefinition(
      sku: "cosmetic_chat_bubble_themes",
      costPoints: 30,
      requiresBusiness: false,
    ),
    "cosmetic_profile_frames": StoreItemDefinition(
      sku: "cosmetic_profile_frames",
      costPoints: 35,
      requiresBusiness: false,
    ),
    "cosmetic_app_icon_pack": StoreItemDefinition(
      sku: "cosmetic_app_icon_pack",
      costPoints: 45,
      requiresBusiness: false,
    ),
    "service_priority_support_pass": StoreItemDefinition(
      sku: "service_priority_support_pass",
      costPoints: 60,
      requiresBusiness: false,
    ),
    "service_profile_spotlight_week": StoreItemDefinition(
      sku: "service_profile_spotlight_week",
      costPoints: 80,
      requiresBusiness: false,
    ),
    "service_message_boost_pack": StoreItemDefinition(
      sku: "service_message_boost_pack",
      costPoints: 70,
      requiresBusiness: false,
    ),
    "service_single_keyword_match_unlock": StoreItemDefinition(
      sku: "service_single_keyword_match_unlock",
      costPoints: 65,
      requiresBusiness: false,
    ),
    "service_reciprocal_match_unlock": StoreItemDefinition(
      sku: "service_reciprocal_match_unlock",
      costPoints: 110,
      requiresBusiness: false,
    ),
    "service_keyword_chain_unlock": StoreItemDefinition(
      sku: "service_keyword_chain_unlock",
      costPoints: 140,
      requiresBusiness: false,
    ),
    "biz_boost_visibility": StoreItemDefinition(
      sku: "biz_boost_visibility",
      costPoints: 40,
      requiresBusiness: true,
    ),
    "biz_provider_tools": StoreItemDefinition(
      sku: "biz_provider_tools",
      costPoints: 60,
      requiresBusiness: true,
    ),
    "biz_high_radius_unlock": StoreItemDefinition(
      sku: "biz_high_radius_unlock",
      costPoints: 90,
      requiresBusiness: true,
    ),
    "biz_discount_author": StoreItemDefinition(
      sku: "biz_discount_author",
      costPoints: 120,
      requiresBusiness: true,
    ),
    "biz_flash_sale_scheduler": StoreItemDefinition(
      sku: "biz_flash_sale_scheduler",
      costPoints: 140,
      requiresBusiness: true,
    ),
    "biz_promo_code_builder": StoreItemDefinition(
      sku: "biz_promo_code_builder",
      costPoints: 90,
      requiresBusiness: true,
    ),
    "biz_lead_filters_pro": StoreItemDefinition(
      sku: "biz_lead_filters_pro",
      costPoints: 110,
      requiresBusiness: true,
    ),
    "biz_auto_reply_templates": StoreItemDefinition(
      sku: "biz_auto_reply_templates",
      costPoints: 95,
      requiresBusiness: true,
    ),
    "biz_campaign_analytics": StoreItemDefinition(
      sku: "biz_campaign_analytics",
      costPoints: 180,
      requiresBusiness: true,
    ),
    "biz_priority_listing_bundle": StoreItemDefinition(
      sku: "biz_priority_listing_bundle",
      costPoints: 220,
      requiresBusiness: true,
    ),
    "biz_multi_location_profile": StoreItemDefinition(
      sku: "biz_multi_location_profile",
      costPoints: 160,
      requiresBusiness: true,
    ),
    "biz_customer_recovery_tools": StoreItemDefinition(
      sku: "biz_customer_recovery_tools",
      costPoints: 150,
      requiresBusiness: true,
    ),
  };

  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  Future<bool> isOwned({required String uid, required String sku}) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty || sku.trim().isEmpty) return false;

    final purchaseRef = _fs
        .collection("users")
        .doc(cleanUid)
        .collection("store")
        .doc("purchases")
        .collection("items")
        .doc(sku);

    try {
      final snap = await purchaseRef.get();
      return snap.exists;
    } catch (_) {
      return false;
    }
  }

  final Map<String, Future<StorePurchaseResult>> _inFlight = {};

  Future<StorePurchaseResult> purchase({required String uid, required String sku,
      required bool businessUnlocked}) {
    final key = "$uid:$sku";
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final next = _purchase(uid: uid, sku: sku, businessUnlocked: businessUnlocked);
    _inFlight[key] = next;
    return next.whenComplete(() { if (identical(_inFlight[key], next)) _inFlight.remove(key); });
  }

  Future<StorePurchaseResult> _purchase({required String uid, required String sku,
      required bool businessUnlocked}) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) throw StateError("Sign in to purchase.");
    final item = _catalog[sku];
    if (item == null) return const StorePurchaseResult(StorePurchaseStatus.unknownSku);
    if (item.requiresBusiness && !businessUnlocked) return const StorePurchaseResult(StorePurchaseStatus.locked);
    final preferences = await SharedPreferences.getInstance();
    final key = "pending_purchase:$uid:$sku";
    // Retain the request after an ambiguous timeout so retry cannot debit twice.
    final requestId = preferences.getString(key) ?? _fs.collection("purchaseIds").doc().id;
    await preferences.setString(key, requestId);
    try {
      final response = await FirebaseFunctions.instanceFor(region: "us-central1")
          .httpsCallable("purchaseWithPoints", options: HttpsCallableOptions(timeout: const Duration(seconds: 20)))
          .call<dynamic>({"sku": sku, "requestId": requestId});
      final data = response.data;
      if (data is! Map || data["purchased"] != true) throw StateError("Purchase has not been confirmed.");
      await preferences.remove(key);
      // A refresh failure cannot turn a confirmed purchase into a failed purchase.
      try { await PointsService.instance.refreshMeta(uid); } catch (_) {}
      return StorePurchaseResult(data["alreadyOwned"] == true
          ? StorePurchaseStatus.alreadyOwned : StorePurchaseStatus.purchased,
          pointsSpent: (data["pointsSpent"] as num?)?.toInt() ?? 0);
    } on FirebaseFunctionsException catch (error) {
      if (error.code == "failed-precondition" &&
          (error.message ?? "").toLowerCase().contains("not enough points")) {
        await preferences.remove(key);
        return const StorePurchaseResult(StorePurchaseStatus.insufficientPoints);
      }
      if (error.code == "permission-denied") {
        await preferences.remove(key);
        return const StorePurchaseResult(StorePurchaseStatus.locked);
      }
      rethrow;
    }
  }

  Future<StorePurchaseResult> purchaseWithExternalCheckout({required String uid,
    required String sku, required bool businessUnlocked, required String sessionId,
    required String paymentMethodId,
  }) async {
    // Provider payment verification is authoritative. Never charge points as a card fallback.
    if (FirebaseAuth.instance.currentUser?.uid != uid || sessionId.trim().isEmpty) {
      throw StateError("A verified checkout session is required.");
    }
    final session = await _fs.doc("users/$uid/billing/externalCheckout/items/$sessionId")
        .get(const GetOptions(source: Source.server));
    final data = session.data();
    if (data?["sku"] != sku || data?["status"] != "paid") {
      throw StateError("Payment is awaiting verification. Check your receipt and try again.");
    }
    if (!await isOwned(uid: uid, sku: sku)) {
      throw StateError("Payment was received; the item is awaiting fulfillment.");
    }
    return const StorePurchaseResult(StorePurchaseStatus.alreadyOwned);
  }

  Future<void> resetStoreStateForUser({required String uid}) async {
    throw StateError("Store resets require an administrator and cannot run from the app.");
  }
}
