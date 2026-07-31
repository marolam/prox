import "package:firebase_auth/firebase_auth.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter/material.dart";
import "package:url_launcher/url_launcher.dart";

import "package:prox/bootstrap/nearby_bootstrap.dart";
import "package:prox/services/business_mode/business_mode_eligibility.dart";
import "package:prox/services/monetization_service.dart";
import "package:prox/services/points_service.dart";
import "package:prox/services/presence_writer.dart";
import "package:prox/release/release_flags.dart";
import "package:prox/services/store_purchase_service.dart";
import "package:prox/services/ui_telemetry_service.dart";
import "package:prox/services/user_profile_service.dart";
import "package:prox/services/user_settings_service.dart";
import "package:prox/screens/monetization/business_paywall_screen.dart";
import "package:prox/widgets/business_mode_gate.dart";
import "package:prox/widgets/tester_badge.dart";
import "package:prox/widgets/store_locked_sheet.dart";

enum _StoreCheckoutMode { points, savedCard }

class ProxPointsStoreScreen extends StatefulWidget {
  final String? debugUidOverride;
  final Future<bool> Function(String uid)? storeUnlockedOverride;
  final Future<void> Function(BuildContext context)? openBillingActivationOverride;
  final WidgetBuilder? unlockedBodyOverride;

  const ProxPointsStoreScreen({
    super.key,
    this.debugUidOverride,
    this.storeUnlockedOverride,
    this.openBillingActivationOverride,
    this.unlockedBodyOverride,
  });

  @override
  State<ProxPointsStoreScreen> createState() => _ProxPointsStoreScreenState();
}

class _ProxPointsStoreScreenState extends State<ProxPointsStoreScreen> {
  bool _testerActionInFlight = false;
  String _purchaseInFlightSku = "";
  int _currentPoints = 0;
  Set<String> _ownedSkus = <String>{};
  bool _loadingCards = false;
  List<Map<String, String>> _cardsOnFile = const <Map<String, String>>[];
  String? _selectedPaymentMethodId;
  _StoreCheckoutMode _checkoutMode = _StoreCheckoutMode.points;
  static const Set<String> _terminalFailureStatuses = <String>{
    "canceled",
    "cancelled",
    "unpaid",
    "past_due",
    "payment_failed",
    "failed",
  };

  String _resolveUid() {
    final override = widget.debugUidOverride;
    if (override != null) return override;
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? "";
    } catch (_) {
      return "";
    }
  }

  Widget _lockedStoreScaffold(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text("Prox Points Store")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outline.withValues(alpha: 0.24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Store locked until Business activation",
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Confirm Business activation in billing first. This unlocks store and wallet surfaces for this account.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final open = widget.openBillingActivationOverride;
                      if (open != null) {
                        await open(context);
                        return;
                      }
                      await BusinessPaywallScreen.open(context);
                    },
                    icon: const Icon(Icons.lock_open_outlined),
                    label: const Text("Open billing activation"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    UiTelemetryService.instance.log("store_open", meta: {"source": "route"});
    if (widget.debugUidOverride != null) {
      return;
    }
    // ignore: discarded_futures
    _syncHighRadiusEntitlement();
    // ignore: discarded_futures
    _loadCardsOnFile();
  }

  Future<void> _loadCardsOnFile() async {
    final uid = _resolveUid();
    if (uid.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _cardsOnFile = const <Map<String, String>>[];
        _selectedPaymentMethodId = null;
        _loadingCards = false;
      });
      return;
    }

    if (mounted) {
      setState(() => _loadingCards = true);
    }

    final cached =
        await MonetizationService.instance.listPaymentMethodsCached(uid: uid);
    if (mounted && cached.isNotEmpty) {
      final selected = cached.firstWhere(
        (c) => c["isDefault"] == "true",
        orElse: () => cached.first,
      );
      final selectedPmId = (selected["paymentMethodId"] ?? "").trim();
      setState(() {
        _cardsOnFile = cached;
        _selectedPaymentMethodId = selectedPmId.isEmpty ? null : selectedPmId;
      });
    }

    try {
      final cards = await MonetizationService.instance
          .listPaymentMethods(uid: uid)
          .timeout(const Duration(seconds: 8));
      final selected = cards.firstWhere(
        (c) => c["isDefault"] == "true",
        orElse: () => cards.isEmpty ? const <String, String>{} : cards.first,
      );
      final selectedPmId = (selected["paymentMethodId"] ?? "").trim();
      if (!mounted) return;
      setState(() {
        _cardsOnFile = cards;
        _selectedPaymentMethodId = selectedPmId.isEmpty ? null : selectedPmId;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingCards = false);
      }
    }
  }

  String _cardSummary(Map<String, String> card) {
    final brand = (card["brand"] ?? "").trim();
    final last4 = (card["last4"] ?? "").trim();
    final fallback = (card["paymentMethodId"] ?? "").trim();
    final label =
        "${brand.isEmpty ? "card" : brand} ${last4.isEmpty ? "" : "•••• $last4"}"
            .trim();
    return label.isEmpty ? fallback : label;
  }

  Future<void> _selectDefaultCard(String pmId) async {
    if (_purchaseInFlightSku.isNotEmpty || _testerActionInFlight) return;
    final uid = _resolveUid();
    if (uid.trim().isEmpty || pmId.trim().isEmpty) return;

    await MonetizationService.instance.setDefaultPaymentMethodId(
      uid: uid,
      paymentMethodId: pmId,
    );
    await _loadCardsOnFile();
  }

  Future<bool?> _showPostCheckoutPrompt({required String title}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Complete payment in browser"),
        content: Text(
          "After finishing checkout for $title, return here and tap Verify payment.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Later"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Verify payment"),
          ),
        ],
      ),
    );
  }

  Future<StorePurchaseResult> _verifyCardCheckoutForStore({
    required String uid,
    required String sku,
    required String title,
    required String sessionId,
    required bool businessUnlocked,
  }) async {
    final cleanUid = uid.trim();
    final cleanSessionId = sessionId.trim();
    if (cleanUid.isEmpty || cleanSessionId.isEmpty) {
      return const StorePurchaseResult(StorePurchaseStatus.unknownSku);
    }

    final started = DateTime.now();
    while (DateTime.now().difference(started) < const Duration(seconds: 60)) {
      final session = await MonetizationService.instance
          .getExternalCheckoutSession(uid: cleanUid, sessionId: cleanSessionId)
          .timeout(const Duration(seconds: 8));
      final status = (session["status"] ?? "").toString().trim().toLowerCase();

      if (status == "paid") {
        return StorePurchaseService.instance.purchaseWithExternalCheckout(
          uid: cleanUid,
          sku: sku,
          businessUnlocked: businessUnlocked,
          sessionId: cleanSessionId,
          paymentMethodId: _selectedPaymentMethodId ?? "",
        );
      }

      if (_terminalFailureStatuses.contains(status)) {
        if (!mounted) {
          return const StorePurchaseResult(StorePurchaseStatus.unknownSku);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Payment status for $title: $status.")),
        );
        return const StorePurchaseResult(StorePurchaseStatus.unknownSku);
      }

      await Future<void>.delayed(const Duration(seconds: 3));
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Payment is still processing. Verify again shortly.",
          ),
        ),
      );
    }
    return const StorePurchaseResult(StorePurchaseStatus.unknownSku);
  }

  Future<StorePurchaseResult> _purchaseWithSavedCard({
    required String uid,
    required String sku,
    required String title,
    required bool businessUnlocked,
  }) async {
    final paymentMethodId = (_selectedPaymentMethodId ?? "").trim();
    if (paymentMethodId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Add and select a card first.")),
        );
      }
      return const StorePurchaseResult(StorePurchaseStatus.unknownSku);
    }

    try {
      Map<String, String> session;
      try {
        session = await MonetizationService.instance
            .createExternalCheckoutSession(
              uid: uid,
              sku: sku,
              paymentMethodId: paymentMethodId,
            )
            .timeout(const Duration(seconds: 12));
      } catch (_) {
        session = await MonetizationService.instance
            .createExternalCheckoutSession(
              uid: uid,
              sku: sku,
            )
            .timeout(const Duration(seconds: 12));
      }

      final checkoutUrl = (session["checkoutUrl"] ?? "").trim();
      final sessionId = (session["sessionId"] ?? "").trim();

      if (checkoutUrl.isEmpty || sessionId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Checkout is not configured for this build yet.",
              ),
            ),
          );
        }
        return const StorePurchaseResult(StorePurchaseStatus.unknownSku);
      }

      final opened = await launchUrl(
        Uri.parse(checkoutUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        return const StorePurchaseResult(StorePurchaseStatus.unknownSku);
      }

      if (!mounted) {
        return const StorePurchaseResult(StorePurchaseStatus.unknownSku);
      }
      final verifyNow = await _showPostCheckoutPrompt(title: title);
      if (verifyNow != true) {
        return const StorePurchaseResult(StorePurchaseStatus.unknownSku);
      }

      return _verifyCardCheckoutForStore(
        uid: uid,
        sku: sku,
        title: title,
        sessionId: sessionId,
        businessUnlocked: businessUnlocked,
      );
    } catch (_) {
      return const StorePurchaseResult(StorePurchaseStatus.unknownSku);
    }
  }

  Future<void> _applyRuntimeEffectsForSku(String sku) async {
    if (sku == "service_message_boost_pack" ||
        sku == "service_single_keyword_match_unlock" ||
        sku == "service_reciprocal_match_unlock" ||
        sku == "service_keyword_chain_unlock" ||
        sku == "service_top_priority_keywords_unlock" ||
        sku == "service_profile_spotlight_week" ||
        sku == "biz_boost_visibility" ||
        sku == "biz_high_radius_unlock") {
      // ignore: discarded_futures
      proxRestartNearby();
    }
    if (sku == "biz_boost_visibility") {
      // ignore: discarded_futures
      PresenceWriter.instance
          .writeOneShot(reason: "store_visibility_boost_purchase");
    }
    if (sku == "biz_high_radius_unlock") {
      UserSettingsService.instance.setHighRadiusUnlocked(true);
    }
    if (sku == "service_single_keyword_match_unlock") {
      UserSettingsService.instance.setSingleKeywordMatchUnlocked(true);
    }
    if (sku == "service_reciprocal_match_unlock") {
      UserSettingsService.instance.setReciprocalMatchUnlocked(true);
    }
    if (sku == "service_keyword_chain_unlock") {
      UserSettingsService.instance.setKeywordChainUnlocked(true);
    }
  }

  Future<void> _syncHighRadiusEntitlement() async {
    final uid = _resolveUid();
    if (uid.trim().isEmpty) return;

    final unlocked =
        await MonetizationService.instance.isHighRadiusUnlocked(uid);
    UserSettingsService.instance.setHighRadiusUnlocked(unlocked);
  }

  Future<Map<String, bool>> _loadBusinessUtilityFlags(String uid) async {
    if (uid.trim().isEmpty) {
      return const <String, bool>{
        "highRadiusUnlocked": false,
        "cosmeticProfileGlowEnabled": false,
        "cosmeticBeaconPaletteEnabled": false,
        "cosmeticChatBubbleThemesEnabled": false,
        "cosmeticProfileFramesEnabled": false,
        "cosmeticAppIconPackEnabled": false,
        "servicePrioritySupportPassEnabled": false,
        "serviceProfileSpotlightWeekEnabled": false,
        "serviceMessageBoostPackEnabled": false,
        "singleKeywordMatchModeUnlocked": false,
        "reciprocalKeywordMatchModeUnlocked": false,
        "keywordChainMatchModeUnlocked": false,
        "topPriorityKeywordsUnlocked": false,
        "bizBoostVisibilityEnabled": false,
        "bizProviderToolsEnabled": false,
        "bizDiscountAuthorEnabled": false,
        "bizFlashSaleSchedulerEnabled": false,
        "bizPromoCodeBuilderEnabled": false,
        "bizLeadFiltersProEnabled": false,
        "bizAutoReplyTemplatesEnabled": false,
        "bizCampaignAnalyticsEnabled": false,
        "bizPriorityListingBundleEnabled": false,
        "bizMultiLocationProfileEnabled": false,
        "bizCustomerRecoveryToolsEnabled": false,
      };
    }

    final data =
        await MonetizationService.instance.getEntitlementsMap(uid: uid);
    return <String, bool>{
      "highRadiusUnlocked": data["highRadiusUnlocked"] == true,
      "cosmeticProfileGlowEnabled": data["cosmeticProfileGlowEnabled"] == true,
      "cosmeticBeaconPaletteEnabled":
          data["cosmeticBeaconPaletteEnabled"] == true,
      "cosmeticChatBubbleThemesEnabled":
          data["cosmeticChatBubbleThemesEnabled"] == true,
      "cosmeticProfileFramesEnabled":
          data["cosmeticProfileFramesEnabled"] == true,
      "cosmeticAppIconPackEnabled": data["cosmeticAppIconPackEnabled"] == true,
      "servicePrioritySupportPassEnabled":
          data["servicePrioritySupportPassEnabled"] == true,
      "serviceProfileSpotlightWeekEnabled":
          data["serviceProfileSpotlightWeekEnabled"] == true,
      "serviceMessageBoostPackEnabled":
          data["serviceMessageBoostPackEnabled"] == true,
      "singleKeywordMatchModeUnlocked":
          data["singleKeywordMatchModeUnlocked"] == true,
      "reciprocalKeywordMatchModeUnlocked":
          data["reciprocalKeywordMatchModeUnlocked"] == true,
      "keywordChainMatchModeUnlocked":
          data["keywordChainMatchModeUnlocked"] == true,
      "topPriorityKeywordsUnlocked":
          data["topPriorityKeywordsUnlocked"] == true,
      "bizBoostVisibilityEnabled": data["bizBoostVisibilityEnabled"] == true,
      "bizProviderToolsEnabled": data["bizProviderToolsEnabled"] == true,
      "bizDiscountAuthorEnabled": data["bizDiscountAuthorEnabled"] == true,
      "bizFlashSaleSchedulerEnabled":
          data["bizFlashSaleSchedulerEnabled"] == true,
      "bizPromoCodeBuilderEnabled": data["bizPromoCodeBuilderEnabled"] == true,
      "bizLeadFiltersProEnabled": data["bizLeadFiltersProEnabled"] == true,
      "bizAutoReplyTemplatesEnabled":
          data["bizAutoReplyTemplatesEnabled"] == true,
      "bizCampaignAnalyticsEnabled":
          data["bizCampaignAnalyticsEnabled"] == true,
      "bizPriorityListingBundleEnabled":
          data["bizPriorityListingBundleEnabled"] == true,
      "bizMultiLocationProfileEnabled":
          data["bizMultiLocationProfileEnabled"] == true,
      "bizCustomerRecoveryToolsEnabled":
          data["bizCustomerRecoveryToolsEnabled"] == true,
    };
  }

  Future<void> _handleTap({
    required BuildContext context,
    required String sku,
    String title = "this item",
    required bool requiresBusiness,
    required bool businessUnlocked,
    bool ownedHint = false,
  }) async {
    if (_purchaseInFlightSku.isNotEmpty) return;

    UiTelemetryService.instance.log(
      "store_item_tap",
      meta: {"sku": sku},
    );

    final uid = _resolveUid();
    if (uid.trim().isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sign in to make purchases.")),
      );
      return;
    }

    bool owned = ownedHint;
    if (!owned) {
      owned = await StorePurchaseService.instance.isOwned(uid: uid, sku: sku);
    }

    if (!owned && sku == "service_top_priority_keywords_unlock") {
      final profile = await UserProfileService.instance.getProfileOnce(uid);
      final bool eligible = (profile?.searchingFor.isNotEmpty ?? false) &&
          (profile?.canProvide.isNotEmpty ?? false);
      if (!eligible) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Add at least one Looking For and one Can Provide keyword before buying this unlock.",
            ),
          ),
        );
        return;
      }
    }

    if (!owned && requiresBusiness && !businessUnlocked) {
      UiTelemetryService.instance.log(
        "store_locked_business",
        meta: {"sku": sku},
      );

      await StoreLockedSheet.show(
        context,
        title: "Coming soon",
        body:
            "Business Mode features are coming soon and temporarily disabled for tester release readiness.\n\n"
            "Please check back in a future build.",
        onGoToAccount: () => Navigator.of(context).pushNamed("/account"),
      );
      return;
    }

    if (mounted) {
      setState(() => _purchaseInFlightSku = sku);
    }

    late final StorePurchaseResult result;
    bool purchaseTimedOut = false;
    final timeout = ReleaseFlags.permissiveTesterUX
        ? const Duration(seconds: 10)
        : const Duration(seconds: 35);
    try {
      if (!requiresBusiness && _checkoutMode == _StoreCheckoutMode.savedCard) {
        result = await _purchaseWithSavedCard(
          uid: uid,
          sku: sku,
          title: title,
          businessUnlocked: businessUnlocked,
        );
      } else {
        result = await StorePurchaseService.instance
            .purchase(
          uid: uid,
          sku: sku,
          businessUnlocked: businessUnlocked,
        )
            .timeout(
          timeout,
          onTimeout: () {
            purchaseTimedOut = true;
            return const StorePurchaseResult(StorePurchaseStatus.unknownSku);
          },
        );
      }
    } catch (e) {
      UiTelemetryService.instance.log(
        "store_purchase_exception",
        meta: {"sku": sku, "error": e.toString()},
      );
      if (mounted) {
        setState(() => _purchaseInFlightSku = "");
      }
      if (!context.mounted) return;
      final msg = e.toString().toLowerCase().contains("timeout")
          ? "Purchase is taking too long. Check connection and try again."
          : "Purchase failed: $e";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      return;
    }

    if (mounted) {
      setState(() => _purchaseInFlightSku = "");
    }

    if (!context.mounted) return;

    if (purchaseTimedOut) {
      UiTelemetryService.instance.log(
        "store_purchase_timeout",
        meta: {"sku": sku},
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Purchase timed out. Please retry in a few seconds."),
        ),
      );
      return;
    }

    switch (result.status) {
      case StorePurchaseStatus.purchased:
        await _applyRuntimeEffectsForSku(sku);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text("Purchased $sku for ${result.pointsSpent} points.")),
        );
        break;
      case StorePurchaseStatus.alreadyOwned:
        await _applyRuntimeEffectsForSku(sku);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Already owned. Runtime effects re-applied.")),
        );
        break;
      case StorePurchaseStatus.insufficientPoints:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Not enough points for this purchase.")),
        );
        break;
      case StorePurchaseStatus.locked:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Business Mode is coming soon for this item.")),
        );
        break;
      case StorePurchaseStatus.unknownSku:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("This store item is currently unavailable.")),
        );
        break;
    }
  }

  void _usePurchasedItem(BuildContext context, String sku) {
    UiTelemetryService.instance.log("store_use_now", meta: {"sku": sku});

    if (sku == "service_priority_support_pass") {
      Navigator.of(context).pushNamed("/support");
      return;
    }

    if (sku == "service_profile_spotlight_week" ||
        sku == "cosmetic_profile_glow" ||
        sku == "cosmetic_beacon_palette" ||
        sku == "cosmetic_chat_bubble_themes" ||
        sku == "cosmetic_profile_frames" ||
        sku == "cosmetic_app_icon_pack") {
      Navigator.of(context).pushNamed("/settings");
      return;
    }

    if (sku == "service_message_boost_pack" ||
        sku == "service_single_keyword_match_unlock" ||
        sku == "service_reciprocal_match_unlock" ||
        sku == "service_keyword_chain_unlock" ||
        sku == "service_top_priority_keywords_unlock" ||
        sku == "biz_boost_visibility" ||
        sku == "biz_provider_tools" ||
        sku == "biz_high_radius_unlock" ||
        sku.startsWith("biz_")) {
      Navigator.of(context).pushNamed("/nearby");
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text(
              "Item is owned. Open Nearby, Settings, or Support to use it.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final uid = _resolveUid();

    Widget tile({
      required String sku,
      required String title,
      required String subtitle,
      required String cost,
      required IconData icon,
      required String category,
      required bool requiresBusiness,
      required bool businessUnlocked,
      int? pointsCost,
      bool owned = false,
    }) {
      final bool unlockedByBusinessGate =
          requiresBusiness && businessUnlocked && pointsCost == null;
      final bool effectiveOwned = owned ||
          _ownedSkus.contains(sku) ||
          unlockedByBusinessGate;
      final bool lockedByBusiness =
          requiresBusiness && !businessUnlocked;
      final bool cardCheckoutActive =
          !requiresBusiness && _checkoutMode == _StoreCheckoutMode.savedCard;
      final bool hasEnoughPoints = pointsCost == null ||
          cardCheckoutActive ||
          _currentPoints >= pointsCost;
      final bool lockedByPoints =
          !effectiveOwned && !cardCheckoutActive && !hasEnoughPoints;
      final bool canBuy =
          !effectiveOwned && !lockedByBusiness && !lockedByPoints;

      Color costColor;
      if (effectiveOwned) {
        costColor = Colors.green;
      } else if (pointsCost != null) {
        costColor = hasEnoughPoints ? Colors.green : cs.error;
      } else if (lockedByBusiness) {
        costColor = Colors.orange;
      } else {
        costColor = cs.onSurfaceVariant;
      }

      final Color borderColor = lockedByBusiness
          ? Colors.orange.withValues(alpha: 0.65)
          : lockedByPoints
              ? cs.error.withValues(alpha: 0.55)
              : effectiveOwned
                  ? Colors.green.withValues(alpha: 0.55)
                  : cs.outline.withValues(alpha: 0.22);

      final String lockReason = lockedByBusiness
          ? "Business Mode coming soon"
          : lockedByPoints
              ? "Need ${pointsCost - _currentPoints} more points"
              : "";

      VoidCallback? tileTap;
      if (_purchaseInFlightSku.isNotEmpty) {
        tileTap = null;
      } else if (effectiveOwned) {
        tileTap = () => _usePurchasedItem(context, sku);
      } else if (lockedByPoints) {
        tileTap = null;
      } else {
        tileTap = () => _handleTap(
              context: context,
              sku: sku,
              title: title,
              requiresBusiness: requiresBusiness,
              businessUnlocked: businessUnlocked,
              ownedHint: owned,
            );
      }

      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: tileTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: lockedByBusiness
                    ? Colors.orange
                    : lockedByPoints
                        ? cs.error
                        : cs.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (effectiveOwned)
                          const TesterBadge(
                            label: "Owned",
                            semanticsLabel: "Item already owned",
                          )
                        else if (requiresBusiness)
                          TesterBadge(
                            label: lockedByBusiness ? "Locked" : "Biz",
                            semanticsLabel: lockedByBusiness
                                ? "Business Mode coming soon"
                                : "Business Mode coming soon",
                          )
                        else
                          const TesterBadge(
                              label: "Buy", semanticsLabel: "Available to buy"),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      category,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Text(
                      "Cost: $cost",
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: costColor,
                      ),
                    ),
                    if (lockReason.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        lockReason,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: lockedByBusiness ? Colors.orange : cs.error,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_purchaseInFlightSku == sku)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (effectiveOwned)
                FilledButton.icon(
                  onPressed: () => _usePurchasedItem(context, sku),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text("Use"),
                )
              else if (canBuy)
                FilledButton(
                  onPressed: () => _handleTap(
                    context: context,
                    sku: sku,
                    title: title,
                    requiresBusiness: requiresBusiness,
                    businessUnlocked: businessUnlocked,
                    ownedHint: owned,
                  ),
                  child: const Text("Buy"),
                )
              else
                OutlinedButton(
                  onPressed: lockedByBusiness
                      ? () => _handleTap(
                            context: context,
                            sku: sku,
                            requiresBusiness: requiresBusiness,
                            businessUnlocked: businessUnlocked,
                            ownedHint: owned,
                          )
                      : null,
                  child: Text(lockedByBusiness ? "Soon" : "Need pts"),
                ),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<bool>(
      future: uid.trim().isEmpty
        ? Future<bool>.value(false)
        : widget.storeUnlockedOverride != null
          ? widget.storeUnlockedOverride!(uid)
          : MonetizationService.instance.isBusinessStoreUnlocked(uid),
      builder: (context, storeUnlockSnap) {
        if (uid.trim().isEmpty) {
          return const Scaffold(
            body: Center(child: Text("Sign in to view the store.")),
          );
        }

        if (storeUnlockSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final storeUnlocked = storeUnlockSnap.data == true;
        if (!storeUnlocked) {
          return _lockedStoreScaffold(context);
        }

        if (widget.unlockedBodyOverride != null) {
          return widget.unlockedBodyOverride!(context);
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection("users")
              .doc(uid)
              .collection("store")
              .doc("purchases")
              .collection("items")
              .snapshots(),
          builder: (context, ownedSnap) {
            _ownedSkus =
                ownedSnap.data?.docs.map((d) => d.id).toSet() ?? <String>{};
            return StreamBuilder<PointsMeta>(
              stream: PointsService.instance.watchMeta(uid),
              builder: (context, snap) {
                final meta = snap.data ?? PointsService.instance.peekMeta(uid);
                _currentPoints = meta.currentPoints;
                return FutureBuilder<BusinessGateState>(
                  future:
                      BusinessModeEligibility.gateForUser(uid: uid, meta: meta),
                  builder: (context, gateSnap) {
                    final gate =
                        gateSnap.data ?? BusinessModeEligibility.gateFromMeta(meta);
                    final businessUnlocked = gate == BusinessGateState.eligible ||
                        gate == BusinessGateState.active;
                    final businessPurchaseAllowed = false;

                    return Scaffold(
                  appBar: AppBar(title: const Text("Prox Points Store")),
                  body: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      Text(
                        "Available unlocks",
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Use points or a saved card for eligible personal items. Purchases are saved to your account.",
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: cs.outline.withValues(alpha: 0.22)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Checkout mode",
                              style: theme.textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 8),
                            SegmentedButton<_StoreCheckoutMode>(
                              segments: const [
                                ButtonSegment<_StoreCheckoutMode>(
                                  value: _StoreCheckoutMode.points,
                                  label: Text("Points"),
                                  icon: Icon(Icons.stars_outlined),
                                ),
                                ButtonSegment<_StoreCheckoutMode>(
                                  value: _StoreCheckoutMode.savedCard,
                                  label: Text("Saved card"),
                                  icon: Icon(Icons.credit_card_outlined),
                                ),
                              ],
                              selected: <_StoreCheckoutMode>{_checkoutMode},
                              onSelectionChanged: (selection) {
                                final next = selection.isEmpty
                                    ? _StoreCheckoutMode.points
                                    : selection.first;
                                setState(() => _checkoutMode = next);
                              },
                            ),
                            if (_checkoutMode == _StoreCheckoutMode.savedCard) ...[
                              const SizedBox(height: 10),
                              if (_loadingCards)
                                const LinearProgressIndicator(minHeight: 2)
                              else if (_cardsOnFile.isEmpty)
                                Text(
                                  "No cards on file. Add one in Account > Payment methods.",
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                )
                              else
                                DropdownButtonFormField<String>(
                                  initialValue: _selectedPaymentMethodId,
                                  decoration: const InputDecoration(
                                    labelText: "Card for checkout",
                                  ),
                                  items: _cardsOnFile
                                      .map(
                                        (card) => DropdownMenuItem<String>(
                                          value: (card["paymentMethodId"] ?? "")
                                              .trim(),
                                          child: Text(_cardSummary(card)),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return;
                                    }
                                    setState(() => _selectedPaymentMethodId = value);
                                    _selectDefaultCard(value);
                                  },
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: cs.outline.withValues(alpha: 0.22)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Store state legend",
                              style: theme.textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                _legendPill(
                                  context,
                                  color: Colors.green,
                                  label: "Green = available / owned",
                                ),
                                _legendPill(
                                  context,
                                  color: cs.error,
                                  label: "Red = not enough points",
                                ),
                                _legendPill(
                                  context,
                                  color: Colors.orange,
                                  label: "Orange = extra unlock required",
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: cs.primary.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.person_outline, color: cs.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Personal items",
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Cosmetics",
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "cosmetic_profile_glow",
                        title: "Profile Glow",
                        subtitle: "Cosmetic highlight.",
                        cost: "15 pts",
                        pointsCost: 15,
                        icon: Icons.auto_awesome_outlined,
                        category: "Personal  Cosmetic",
                        requiresBusiness: false,
                        businessUnlocked: businessUnlocked,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "cosmetic_beacon_palette",
                        title: "Beacon Palette",
                        subtitle: "Extra beacon colors.",
                        cost: "25 pts",
                        pointsCost: 25,
                        icon: Icons.palette_outlined,
                        category: "Personal  Cosmetic",
                        requiresBusiness: false,
                        businessUnlocked: businessUnlocked,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "cosmetic_chat_bubble_themes",
                        title: "Chat Bubble Themes",
                        subtitle: "Personalized chat accent themes.",
                        cost: "30 pts",
                        pointsCost: 30,
                        icon: Icons.chat_bubble_outline,
                        category: "Personal  Cosmetic",
                        requiresBusiness: false,
                        businessUnlocked: businessUnlocked,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "cosmetic_profile_frames",
                        title: "Profile Frames Pack",
                        subtitle: "Distinctive frame styles for your profile.",
                        cost: "35 pts",
                        pointsCost: 35,
                        icon: Icons.crop_square,
                        category: "Personal  Cosmetic",
                        requiresBusiness: false,
                        businessUnlocked: businessUnlocked,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "cosmetic_app_icon_pack",
                        title: "App Icon Pack",
                        subtitle: "Unlock alternate launcher icon set.",
                        cost: "45 pts",
                        pointsCost: 45,
                        icon: Icons.apps,
                        category: "Personal  Cosmetic",
                        requiresBusiness: false,
                        businessUnlocked: businessUnlocked,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        "Services",
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "service_priority_support_pass",
                        title: "Priority Support Pass",
                        subtitle: "Faster first-response support lane.",
                        cost: "60 pts",
                        pointsCost: 60,
                        icon: Icons.support_agent,
                        category: "Personal  Service",
                        requiresBusiness: false,
                        businessUnlocked: businessUnlocked,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "service_profile_spotlight_week",
                        title: "Profile Spotlight (7 days)",
                        subtitle: "Temporary spotlight in discovery surfaces.",
                        cost: "80 pts",
                        pointsCost: 80,
                        icon: Icons.flash_on_outlined,
                        category: "Personal  Service",
                        requiresBusiness: false,
                        businessUnlocked: businessUnlocked,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "service_message_boost_pack",
                        title: "Message Boost Pack",
                        subtitle:
                            "Priority delivery lane for outreach attempts.",
                        cost: "70 pts",
                        pointsCost: 70,
                        icon: Icons.mark_chat_unread_outlined,
                        category: "Personal  Service",
                        requiresBusiness: false,
                        businessUnlocked: businessUnlocked,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "service_single_keyword_match_unlock",
                        title: "Single Keyword Match Unlock",
                        subtitle:
                            "Enable matching when just one active keyword overlaps.",
                        cost: "65 pts",
                        pointsCost: 65,
                        icon: Icons.looks_one_outlined,
                        category: "Personal  Service",
                        requiresBusiness: false,
                        businessUnlocked: businessUnlocked,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "service_reciprocal_match_unlock",
                        title: "Reciprocal Opposite Match Unlock",
                        subtitle:
                            "Require BOTH directions: your Looking For matches their Can Provide and vice versa.",
                        cost: "110 pts",
                        pointsCost: 110,
                        icon: Icons.compare_arrows_outlined,
                        category: "Personal  Service",
                        requiresBusiness: false,
                        businessUnlocked: businessUnlocked,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "service_keyword_chain_unlock",
                        title: "Keyword Chain Unlock",
                        subtitle:
                            "Require a chain of 2+ active shared keywords for higher-intent matches.",
                        cost: "140 pts",
                        pointsCost: 140,
                        icon: Icons.link_outlined,
                        category: "Personal  Service",
                        requiresBusiness: false,
                        businessUnlocked: businessUnlocked,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "service_top_priority_keywords_unlock",
                        title: "Top Priority Keywords Unlock",
                        subtitle:
                            "Enable one starred top-priority keyword in Looking For and Can Provide.",
                        cost: "95 pts",
                        pointsCost: 95,
                        icon: Icons.star_outline,
                        category: "Personal  Service",
                        requiresBusiness: false,
                        businessUnlocked: businessUnlocked,
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.work_outline,
                                color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Business items (Coming soon)",
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ),
                            Text(
                              "Coming soon",
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.orange,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Visibility & discovery",
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      FutureBuilder<Map<String, bool>>(
                        future: _loadBusinessUtilityFlags(uid),
                        builder: (context, entitlementSnap) {
                          final flags =
                              entitlementSnap.data ?? const <String, bool>{};

                          Widget row(String key) {
                            final enabled = flags[key] == true;
                            return Row(
                              children: [
                                Icon(
                                  enabled
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  size: 16,
                                  color: enabled
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "$key: ${enabled ? "true" : "false"}",
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: cs.outline.withValues(alpha: 0.22)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Business utility entitlement check (coming soon)",
                                  style: theme.textTheme.labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                row("bizDiscountAuthorEnabled"),
                                const SizedBox(height: 4),
                                row("bizFlashSaleSchedulerEnabled"),
                                const SizedBox(height: 4),
                                row("bizPromoCodeBuilderEnabled"),
                                const SizedBox(height: 4),
                                row("bizLeadFiltersProEnabled"),
                                const SizedBox(height: 4),
                                row("bizAutoReplyTemplatesEnabled"),
                                const SizedBox(height: 4),
                                row("bizCampaignAnalyticsEnabled"),
                                const SizedBox(height: 4),
                                row("bizPriorityListingBundleEnabled"),
                                const SizedBox(height: 4),
                                row("bizMultiLocationProfileEnabled"),
                                const SizedBox(height: 4),
                                row("bizCustomerRecoveryToolsEnabled"),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "biz_boost_visibility",
                        title: "Business Visibility Boost",
                        subtitle: "Enhanced discovery placement (future).",
                        cost: "Coming soon",
                        icon: Icons.trending_up,
                        category: "Business  Visibility",
                        requiresBusiness: true,
                        businessUnlocked: businessPurchaseAllowed,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "biz_high_radius_unlock",
                        title: "High Radius Unlock",
                        subtitle:
                            "Expands passive business search from 15 to 30 miles.",
                        cost: "90 pts",
                        pointsCost: 90,
                        icon: Icons.radar_outlined,
                        category: "Business  Visibility",
                        requiresBusiness: true,
                        businessUnlocked: businessPurchaseAllowed,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "biz_priority_listing_bundle",
                        title: "Priority Listing Bundle",
                        subtitle:
                            "Bundle uplift for visibility, profile polish, and CTR.",
                        cost: "220 pts",
                        pointsCost: 220,
                        icon: Icons.workspace_premium_outlined,
                        category: "Business  Visibility",
                        requiresBusiness: true,
                        businessUnlocked: businessPurchaseAllowed,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "biz_multi_location_profile",
                        title: "Multi-location Profile",
                        subtitle:
                            "Manage multiple service areas from one account.",
                        cost: "160 pts",
                        pointsCost: 160,
                        icon: Icons.pin_drop_outlined,
                        category: "Business  Visibility",
                        requiresBusiness: true,
                        businessUnlocked: businessPurchaseAllowed,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        "Operations & messaging",
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "biz_provider_tools",
                        title: "Provider Tools Pack",
                        subtitle:
                            "Fast replies, availability presets, and lead tools (future).",
                        cost: "Coming soon",
                        icon: Icons.work_outline,
                        category: "Business  Operations",
                        requiresBusiness: true,
                        businessUnlocked: businessPurchaseAllowed,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "biz_auto_reply_templates",
                        title: "Auto-reply Templates",
                        subtitle:
                            "Saved responses for common customer requests.",
                        cost: "95 pts",
                        pointsCost: 95,
                        icon: Icons.quickreply_outlined,
                        category: "Business  Operations",
                        requiresBusiness: true,
                        businessUnlocked: businessPurchaseAllowed,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "biz_lead_filters_pro",
                        title: "Lead Filters Pro",
                        subtitle:
                            "Advanced filter presets for higher-intent leads.",
                        cost: "110 pts",
                        pointsCost: 110,
                        icon: Icons.filter_alt_outlined,
                        category: "Business  Operations",
                        requiresBusiness: true,
                        businessUnlocked: businessPurchaseAllowed,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "biz_customer_recovery_tools",
                        title: "Customer Recovery Tools",
                        subtitle:
                            "Follow-up tools for missed or expired leads.",
                        cost: "150 pts",
                        pointsCost: 150,
                        icon: Icons.restore_outlined,
                        category: "Business  Operations",
                        requiresBusiness: true,
                        businessUnlocked: businessPurchaseAllowed,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        "Campaigns & promotion",
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "biz_discount_author",
                        title: "Discount Author",
                        subtitle:
                            "Create percentage or fixed discounts for Prox users.",
                        cost: "120 pts",
                        pointsCost: 120,
                        icon: Icons.sell_outlined,
                        category: "Business  Promotion",
                        requiresBusiness: true,
                        businessUnlocked: businessPurchaseAllowed,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "biz_flash_sale_scheduler",
                        title: "Flash Sale Scheduler",
                        subtitle:
                            "Schedule campaign windows with auto start and stop.",
                        cost: "140 pts",
                        pointsCost: 140,
                        icon: Icons.schedule,
                        category: "Business  Promotion",
                        requiresBusiness: true,
                        businessUnlocked: businessPurchaseAllowed,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "biz_promo_code_builder",
                        title: "Promo Code Builder",
                        subtitle: "Create redeemable promo code campaigns.",
                        cost: "90 pts",
                        pointsCost: 90,
                        icon: Icons.qr_code_2,
                        category: "Business  Promotion",
                        requiresBusiness: true,
                        businessUnlocked: businessPurchaseAllowed,
                      ),
                      const SizedBox(height: 10),
                      tile(
                        sku: "biz_campaign_analytics",
                        title: "Campaign Analytics",
                        subtitle:
                            "Performance views for promos and listing conversion.",
                        cost: "180 pts",
                        pointsCost: 180,
                        icon: Icons.analytics_outlined,
                        category: "Business  Promotion",
                        requiresBusiness: true,
                        businessUnlocked: businessPurchaseAllowed,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
      },
    );
  }

  Widget _legendPill(
    BuildContext context, {
    required Color color,
    required String label,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}
