import "package:cloud_firestore/cloud_firestore.dart";

import "package:prox/services/monetization_service.dart";
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

  static const Map<String, String> _boolEntitlements = <String, String>{
    "cosmetic_profile_glow": "cosmeticProfileGlowEnabled",
    "cosmetic_beacon_palette": "cosmeticBeaconPaletteEnabled",
    "cosmetic_chat_bubble_themes": "cosmeticChatBubbleThemesEnabled",
    "cosmetic_profile_frames": "cosmeticProfileFramesEnabled",
    "cosmetic_app_icon_pack": "cosmeticAppIconPackEnabled",
    "service_priority_support_pass": "servicePrioritySupportPassEnabled",
    "service_profile_spotlight_week": "serviceProfileSpotlightWeekEnabled",
    "service_message_boost_pack": "serviceMessageBoostPackEnabled",
    "service_single_keyword_match_unlock": "singleKeywordMatchModeUnlocked",
    "service_reciprocal_match_unlock": "reciprocalKeywordMatchModeUnlocked",
    "service_keyword_chain_unlock": "keywordChainMatchModeUnlocked",
    "biz_boost_visibility": "bizBoostVisibilityEnabled",
    "biz_provider_tools": "bizProviderToolsEnabled",
    "biz_discount_author": "bizDiscountAuthorEnabled",
    "biz_flash_sale_scheduler": "bizFlashSaleSchedulerEnabled",
    "biz_promo_code_builder": "bizPromoCodeBuilderEnabled",
    "biz_lead_filters_pro": "bizLeadFiltersProEnabled",
    "biz_auto_reply_templates": "bizAutoReplyTemplatesEnabled",
    "biz_campaign_analytics": "bizCampaignAnalyticsEnabled",
    "biz_priority_listing_bundle": "bizPriorityListingBundleEnabled",
    "biz_multi_location_profile": "bizMultiLocationProfileEnabled",
    "biz_customer_recovery_tools": "bizCustomerRecoveryToolsEnabled",
  };

  Future<StorePurchaseResult> purchase({
    required String uid,
    required String sku,
    required bool businessUnlocked,
  }) async {
    try {
      final cleanUid = uid.trim();
      if (cleanUid.isEmpty) {
        return const StorePurchaseResult(StorePurchaseStatus.unknownSku);
      }

      final item = _catalog[sku];
      if (item == null) {
        return const StorePurchaseResult(StorePurchaseStatus.unknownSku);
      }

      bool debited = false;
      bool committed = false;

      final purchaseRef = _fs
          .collection("users")
          .doc(cleanUid)
          .collection("store")
          .doc("purchases")
          .collection("items")
          .doc(sku);

      final existing = await purchaseRef.get();
      if (existing.exists) {
        // Self-heal: if purchase doc exists but entitlement flags drifted,
        // re-apply SKU effects so runtime behavior remains consistent.
        await _applyEntitlementsForSku(uid: cleanUid, sku: sku);
        return const StorePurchaseResult(StorePurchaseStatus.alreadyOwned);
      }

      // Business lock applies only to first-time purchases.
      if (item.requiresBusiness && !businessUnlocked) {
        return const StorePurchaseResult(StorePurchaseStatus.locked);
      }

      debited = await PointsService.instance.spendPoints(
        uid: cleanUid,
        amount: item.costPoints,
        reason: "Store purchase: $sku",
        category: "store",
        contextId: sku,
        contextType: "store_purchase",
      );

      if (!debited) {
        return const StorePurchaseResult(
            StorePurchaseStatus.insufficientPoints);
      }

      try {
        await purchaseRef.set(<String, Object?>{
          "sku": sku,
          "costPoints": item.costPoints,
          "requiresBusiness": item.requiresBusiness,
          "purchasedAt": FieldValue.serverTimestamp(),
        });

        await _applyEntitlementsForSku(uid: cleanUid, sku: sku);
        committed = true;
      } catch (_) {
        if (debited && !committed) {
          await PointsService.instance.addPoints(
            uid: cleanUid,
            amount: item.costPoints,
            reason: "Store purchase rollback: $sku",
            category: "store_rollback",
            contextId: sku,
            contextType: "store_purchase_rollback",
          );
        }
        rethrow;
      }

      return StorePurchaseResult(
        StorePurchaseStatus.purchased,
        pointsSpent: item.costPoints,
      );
    } catch (_) {
      return const StorePurchaseResult(StorePurchaseStatus.unknownSku);
    }
  }

  Future<StorePurchaseResult> purchaseWithExternalCheckout({
    required String uid,
    required String sku,
    required bool businessUnlocked,
    required String sessionId,
    required String paymentMethodId,
  }) {
    return purchase(
      uid: uid,
      sku: sku,
      businessUnlocked: businessUnlocked,
    );
  }

  Future<void> _applyEntitlementsForSku({
    required String uid,
    required String sku,
  }) async {
    if (sku == "biz_high_radius_unlock") {
      await MonetizationService.instance.setHighRadiusUnlocked(
        uid: uid,
        unlocked: true,
        sku: sku,
      );
      return;
    }

    final entitlementKey = _boolEntitlements[sku];
    if (entitlementKey == null) return;

    await MonetizationService.instance.setEntitlementBool(
      uid: uid,
      key: entitlementKey,
      value: true,
      sku: sku,
    );
  }

  Future<void> resetStoreStateForUser({required String uid}) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return;

    final itemsRef = _fs
        .collection("users")
        .doc(cleanUid)
        .collection("store")
        .doc("purchases")
        .collection("items");

    final entitlementRef = _fs
        .collection("users")
        .doc(cleanUid)
        .collection("billing")
        .doc("entitlements");

    final snaps = await itemsRef.get();
    final batch = _fs.batch();
    for (final doc in snaps.docs) {
      batch.delete(doc.reference);
    }

    final resetPayload = <String, Object?>{
      "businessPurchased": false,
      "businessSubscriptionActive": false,
      "subscriptionRenewsAt": null,
      "subscriptionStartedAt": null,
      "highRadiusUnlocked": false,
      "lastSku": "tester_store_reset",
      "updatedAt": FieldValue.serverTimestamp(),
    };
    for (final key in _boolEntitlements.values) {
      resetPayload[key] = false;
    }

    batch.set(entitlementRef, resetPayload, SetOptions(merge: true));
    await batch.commit();
  }
}
