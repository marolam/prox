import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/screens/settings/account/buy_points_screen.dart";
import "package:prox/screens/policy/business_rules_screen.dart";
import "package:prox/services/action_receipt_service.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/business_mode/business_mode_state_service.dart";
import "package:prox/screens/services/match_settings_service.dart";
import "package:prox/services/monetization_service.dart";
import "package:prox/services/points_service.dart";
import "package:prox/services/user_settings_service.dart";
import "package:prox/release/release_flags.dart";
import "package:prox/release/rollout_gate_service.dart";
import "package:prox/widgets/tutorial/tutorial_overlay.dart";
import "package:prox/widgets/tutorial/tutorial_target.dart";
import "package:prox/screens/store/feature_example_screen.dart";
import "package:prox/services/pro_mode_preview_access.dart";
import "package:url_launcher/url_launcher.dart";

class BusinessPaywallScreen extends StatefulWidget {
  const BusinessPaywallScreen({super.key});

  static Future<bool?> open(BuildContext context) {
    if (!RolloutGateService.instance.isBusinessModeEnabled ||
        !ProModePreviewAccess.instance.isAllowedForCurrentUser()) {
      return Navigator.of(context).push<bool?>(
        MaterialPageRoute<bool?>(builder: (_) => const FeatureExampleScreen()),
      );
    }
    final previous = ContextHelpService.instance.contextKey.value;
    ContextHelpService.instance.setContext("business:paywall");
    return Navigator.of(context)
        .push<bool?>(
          MaterialPageRoute<bool?>(
            builder: (_) => const BusinessPaywallScreen(),
          ),
        )
        .then((result) {
          ContextHelpService.instance.setContext(previous);
          return result;
        });
  }

  @override
  State<BusinessPaywallScreen> createState() => _BusinessPaywallScreenState();
}

class _BusinessPaywallScreenState extends State<BusinessPaywallScreen> {
  bool _loading = true;
  String? _loadError;
  bool _busy = false;
  bool _unlocked = false;
  String? _lastSku;
  List<Map<String, String>> _cardsOnFile = const <Map<String, String>>[];
  String? _selectedPaymentMethodId;
  String _paymentMode = MonetizationService.paymentModePointsFirst;
  static const Set<String> _terminalFailureStatuses = <String>{
    "canceled",
    "cancelled",
    "unpaid",
    "past_due",
    "payment_failed",
    "failed",
  };

  int _pointsAppliedForMode(int currentPoints) {
    switch (_paymentMode) {
      case MonetizationService.paymentModeCashOnly:
        return 0;
      case MonetizationService.paymentModePointsOnly:
        return MonetizationService.monthlySubscriptionPoints;
      case MonetizationService.paymentModePointsFirst:
      default:
        return currentPoints >= MonetizationService.monthlySubscriptionPoints
            ? MonetizationService.monthlySubscriptionPoints
            : 0;
    }
  }

  double _usdChargeForMode(int currentPoints) {
    if (_paymentMode == MonetizationService.paymentModeCashOnly) {
      return MonetizationService.monthlySubscriptionUsd;
    }
    final pointsApplied = _pointsAppliedForMode(currentPoints);
    return pointsApplied >= MonetizationService.monthlySubscriptionPoints
        ? 0
        : MonetizationService.monthlySubscriptionUsd;
  }

  int _pointsGapForMode(int currentPoints) {
    if (_paymentMode == MonetizationService.paymentModeCashOnly) {
      return MonetizationService.monthlySubscriptionPoints;
    }
    final pointsApplied = _pointsAppliedForMode(currentPoints);
    return MonetizationService.instance.pointsMissingForZeroUsd(pointsApplied);
  }

  Future<void> _confirmActivationStart({
    required String uid,
    required int currentPoints,
  }) async {
    if (_busy) return;

    if (!await ensureBusinessRulesAccepted(context)) return;
    if (!mounted) return;

    final pointsApplied = _pointsAppliedForMode(currentPoints);
    final usdCharge = _usdChargeForMode(currentPoints);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Start Business Mode activation?"),
        content: Text(
          "This purchases 30 days of access after payment is confirmed by the server. Access does not renew automatically.\n\n"
          "Points for this purchase: $pointsApplied\n"
          "Estimated card charge: \$${usdCharge.toStringAsFixed(2)}\n\n"
          "Only continue when you are ready to finish setup now.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Not now"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Confirm and activate"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _subscribeWithSelectedMode();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    if (!ProModePreviewAccess.instance.isAllowedForCurrentUser()) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted)
      setState(() {
        _loading = true;
        _loadError = null;
      });
    try {
      await _loadValues().timeout(const Duration(seconds: 20));
    } catch (_) {
      if (mounted)
        setState(
          () => _loadError =
              "Billing could not be loaded. Check your connection and retry.",
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadValues() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    final svc = MonetizationService.instance;
    final unlocked = await svc.isBusinessUnlocked(uid);
    final lastSku = await svc.getLastSku(uid);
    final cards = await svc.listPaymentMethods(uid: uid);
    final savedPm = await svc.getDefaultPaymentMethod(uid: uid);
    final prefs = await svc.getBillingPreferences(uid: uid);
    final savedPmId = (savedPm["paymentMethodId"] ?? "").trim();
    final selectedFromCards = cards.firstWhere(
      (c) => c["isDefault"] == "true",
      orElse: () => const <String, String>{},
    );
    final selectedPmId = (selectedFromCards["paymentMethodId"] ?? savedPmId)
        .trim();

    if (!mounted) return;
    setState(() {
      _unlocked = unlocked;
      _lastSku = lastSku;
      _cardsOnFile = cards;
      _selectedPaymentMethodId = selectedPmId.isEmpty ? null : selectedPmId;
      _paymentMode =
          (prefs["paymentMode"] ?? MonetizationService.paymentModePointsFirst)
              .toString();
      _loading = false;
    });
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

  Future<void> _saveBillingPreferences() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await MonetizationService.instance.saveBillingPreferences(
      uid: uid,
      autoRenewWithSelectedCard: false,
      paymentMode: _paymentMode,
    );
  }

  Future<void> _selectDefaultCard(String paymentMethodId) async {
    if (_busy) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      await MonetizationService.instance.setDefaultPaymentMethodId(
        uid: uid,
        paymentMethodId: paymentMethodId,
      );
      final cards = await MonetizationService.instance.listPaymentMethods(
        uid: uid,
      );
      if (!mounted) return;
      setState(() {
        _cardsOnFile = cards;
        _selectedPaymentMethodId = paymentMethodId;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startExternalCheckoutWithSavedCard(
    String sku,
    String label,
  ) async {
    if (_busy) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final savedPmId = (_selectedPaymentMethodId ?? "").trim();
    if (savedPmId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Add/select a card on file first, then try again."),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final session = await MonetizationService.instance
          .createExternalCheckoutSession(
            uid: uid,
            sku: sku,
            paymentMethodId: savedPmId,
          );
      final checkoutUrl = (session["checkoutUrl"] ?? "").trim();
      final sessionId = (session["sessionId"] ?? "").trim();

      await ActionReceiptService.instance.add(
        kind: "payment",
        title: "Saved-card checkout session created",
        detail: "Prepared $label with saved card token. sessionId=$sessionId",
      );

      if (!mounted) return;
      if (checkoutUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Saved-card session created for $label. Session: $sessionId",
            ),
          ),
        );
        return;
      }

      final opened = await launchUrl(
        Uri.parse(checkoutUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;

      final verifyNow = await _showPostCheckoutPrompt(
        label: label,
        opened: opened,
      );
      if (verifyNow == true && mounted) {
        await _verifyCheckoutResult(
          uid: uid,
          sessionId: sessionId,
          sku: sku,
          label: label,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _showPostCheckoutPrompt({
    required String label,
    required bool opened,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Complete checkout"),
        content: Text(
          opened
              ? "Finish the $label checkout in your browser, then return here to verify the payment."
              : "Checkout URL is ready but did not open automatically. Open it from the browser prompt, then return here to verify the payment.",
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

  Future<void> _verifyCheckoutResult({
    required String uid,
    required String sessionId,
    required String sku,
    required String label,
  }) async {
    final cleanUid = uid.trim();
    final cleanSessionId = sessionId.trim();
    if (cleanUid.isEmpty || cleanSessionId.isEmpty) return;

    if (mounted) setState(() => _busy = true);
    try {
      final started = DateTime.now();
      while (DateTime.now().difference(started) < const Duration(seconds: 60)) {
        final session = await MonetizationService.instance
            .getExternalCheckoutSession(
              uid: cleanUid,
              sessionId: cleanSessionId,
            )
            .timeout(const Duration(seconds: 8));
        final status = (session["status"] ?? "")
            .toString()
            .trim()
            .toLowerCase();

        if (status == "paid") {
          if (!RolloutGateService.instance.isBusinessModeWriteEnabled) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  RolloutGateService.instance.businessModeDisabledReason,
                ),
              ),
            );
            return;
          }
          await BusinessModeStateService.instance.setActive(cleanUid, true);
          await ActionReceiptService.instance.add(
            kind: "payment",
            title: "Business payment confirmed",
            detail: "$label confirmed. SKU=$sku sessionId=$cleanSessionId.",
          );
          if (!mounted) return;
          setState(() {
            _unlocked = true;
            _lastSku = sku;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Payment confirmed. Business Mode is active."),
            ),
          );
          return;
        }

        if (_terminalFailureStatuses.contains(status)) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Payment status: $status.")));
          return;
        }

        await Future<void>.delayed(const Duration(seconds: 3));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Payment is still processing. Check again shortly after the Square webhook syncs.",
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not verify payment yet: $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openBuyOnePoint() async {
    if (_busy) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const BuyPointsScreen()));
    await _load();
  }

  Future<void> _subscribeWithSelectedMode() async {
    if (_busy) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _saveBillingPreferences();

    if (_paymentMode == MonetizationService.paymentModeCashOnly) {
      await _startExternalCheckoutWithSavedCard(
        "biz_monthly_subscription",
        "30-day access",
      );
      return;
    }

    if (_paymentMode == MonetizationService.paymentModePointsOnly) {
      await _subscribeMonthly();
      return;
    }

    final pointsMeta = await PointsService.instance.getMeta(uid);
    if (pointsMeta.currentPoints >=
        MonetizationService.monthlySubscriptionPoints) {
      await _subscribeMonthly();
      return;
    }

    await _startExternalCheckoutWithSavedCard(
      "biz_monthly_subscription",
      "30-day access",
    );
  }

  Future<void> _buyOneTimeUnlock() async {
    if (_busy) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      bool timedOut = false;
      final ok = await MonetizationService.instance
          .purchaseOneTimeUnlockWithPoints(uid)
          .timeout(
            ReleaseFlags.permissiveTesterUX
                ? const Duration(seconds: 10)
                : const Duration(seconds: 35),
            onTimeout: () {
              timedOut = true;
              return false;
            },
          );

      if (timedOut) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Purchase could not be confirmed. Refresh billing before retrying.",
            ),
          ),
        );
        return;
      }

      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Not enough points. Need ${MonetizationService.oneTimeUnlockPoints} points for one-time unlock.",
            ),
          ),
        );
        return;
      }

      await ActionReceiptService.instance.add(
        kind: "payment",
        title: "Business unlocked (one-time)",
        detail:
            "One-time unlock completed with points. SKU=biz_onetime_unlock.",
      );

      if (!mounted) return;
      setState(() {
        _unlocked = true;
        _lastSku = "biz_onetime_unlock";
      });

      Navigator.of(context).pop(true);
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _subscribeMonthly() async {
    if (_busy) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      bool timedOut = false;
      final ok = await MonetizationService.instance
          .startMonthlySubscriptionWithPoints(uid)
          .timeout(
            ReleaseFlags.permissiveTesterUX
                ? const Duration(seconds: 10)
                : const Duration(seconds: 35),
            onTimeout: () {
              timedOut = true;
              return false;
            },
          );

      if (timedOut) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Purchase could not be confirmed. Refresh billing before retrying.",
            ),
          ),
        );
        return;
      }

      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Not enough points. Need ${MonetizationService.monthlySubscriptionPoints} points for 30-day access.",
            ),
          ),
        );
        return;
      }

      await ActionReceiptService.instance.add(
        kind: "payment",
        title: "30-day access activated",
        detail:
            "30-day access activated with points. SKU=biz_monthly_subscription.",
      );

      if (!mounted) return;
      setState(() {
        _unlocked = true;
        _lastSku = "biz_monthly_subscription";
      });

      Navigator.of(context).pop(true);
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startExternalCheckout(String sku, String label) async {
    if (_busy) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      final session = await MonetizationService.instance
          .createExternalCheckoutSession(uid: uid, sku: sku);
      final sessionId = (session["sessionId"] ?? "").trim();
      final checkoutUrl = (session["checkoutUrl"] ?? "").trim();

      await ActionReceiptService.instance.add(
        kind: "payment",
        title: "External checkout intent created",
        detail: checkoutUrl.isEmpty
            ? "Prepared $label via provider scaffold. sessionId=$sessionId"
            : "Prepared $label checkout session. sessionId=$sessionId",
      );

      if (!mounted) return;
      if (checkoutUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "External checkout session created ($label). Session: $sessionId",
            ),
          ),
        );
        return;
      }

      final opened = await launchUrl(
        Uri.parse(checkoutUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;

      final verifyNow = await _showPostCheckoutPrompt(
        label: label,
        opened: opened,
      );
      if (verifyNow == true && mounted) {
        await _verifyCheckoutResult(
          uid: uid,
          sessionId: sessionId,
          sku: sku,
          label: label,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activateBusinessRoiNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final userSettings = UserSettingsService.instance;
      MatchSettingsService.instance.setBusinessOnly(true);
      userSettings.setMatchingMode(MatchingModeKind.normal);
      userSettings.setNormalMatchMode(NormalMatchMode.active);

      await ActionReceiptService.instance.add(
        kind: "business",
        title: "Business ROI mode started",
        detail:
            "Business-only filter enabled and matching set to Normal Active.",
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      Navigator.of(context).pushNamed("/nearby");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";

    if (!ProModePreviewAccess.instance.isAllowedForCurrentUser()) {
      return const FeatureExampleScreen();
    }
    final scaffold = Scaffold(
      appBar: AppBar(title: const Text("Business Mode")),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_loadError!),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _load,
                        child: const Text("Retry"),
                      ),
                    ],
                  ),
                ),
              )
            : FutureBuilder<PointsMeta>(
                future: uid.trim().isEmpty
                    ? Future<PointsMeta>.value(PointsMeta.empty)
                    : PointsService.instance.getMeta(uid),
                builder: (context, pointsSnap) {
                  final pointsMeta = pointsSnap.data ?? PointsMeta.empty;
                  final currentPoints = pointsMeta.currentPoints;
                  final pointsApplied = _pointsAppliedForMode(currentPoints);
                  final usdCharge = _usdChargeForMode(currentPoints);
                  final pointsGap = _pointsGapForMode(currentPoints);
                  final referralsNeeded = MonetizationService.instance
                      .referralsNeededForPointsGap(pointsGap);
                  final supportNeeded = MonetizationService.instance
                      .supportTicketsNeededForPointsGap(pointsGap);

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: cs.outline.withValues(alpha: 0.30),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.bolt, color: cs.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _unlocked
                                        ? "Business Mode is unlocked"
                                        : "Unlock Business Mode",
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "Business Mode is the revenue path: purpose-focused meetups, provider visibility, and business-only discovery filters.",
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  if (_lastSku != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      "Last activation: $_lastSku",
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: cs.outline.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Activation preview",
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Price: \$${MonetizationService.monthlySubscriptionUsd.toStringAsFixed(2)} or ${MonetizationService.monthlySubscriptionPoints} points for 30 days",
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Current wallet: $currentPoints points",
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "This cycle: $pointsApplied points + \$${usdCharge.toStringAsFixed(2)} card",
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "To cover a 30-day purchase with points only: $pointsGap additional points",
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Estimated effort: $referralsNeeded confirmed referrals or $supportNeeded completed support tickets.",
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "Eligible rewards can contribute to a 30-day access purchase after server verification.",
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _busy || uid.trim().isEmpty
                                    ? null
                                    : () => _confirmActivationStart(
                                        uid: uid,
                                        currentPoints: currentPoints,
                                      ),
                                icon: const Icon(Icons.verified_outlined),
                                label: const Text("Review 30-day activation"),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Choose an option",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _PayOptionCard(
                        title: "30-day access (selected payment mode)",
                        subtitle:
                            "Uses your selected payment mode: points only, cash only, or points first fallback.",
                        cta: "Subscribe now",
                        icon: Icons.account_balance_wallet_outlined,
                        busy: _busy,
                        onTap: _subscribeWithSelectedMode,
                      ),
                      const SizedBox(height: 10),
                      TutorialTarget(
                        id: "paywall.monthly",
                        message:
                            "30-day access\n\nActivates Business Mode for 30 days using Prox Points.",
                        child: _PayOptionCard(
                          title: "30-day access",
                          subtitle:
                              "Prepaid access for 30 days. No automatic renewal. Cost: ${MonetizationService.monthlySubscriptionPoints} points or \$${MonetizationService.monthlySubscriptionUsd.toStringAsFixed(2)}.",
                          cta: "Subscribe with points",
                          icon: Icons.calendar_month,
                          busy: _busy,
                          onTap: _subscribeMonthly,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TutorialTarget(
                        id: "paywall.onetime",
                        message:
                            "One-time unlock\n\nPermanent unlock for this account using Prox Points.",
                        child: _PayOptionCard(
                          title: "One-time unlock",
                          subtitle:
                              "Unlock Business Mode permanently for this account. Cost: ${MonetizationService.oneTimeUnlockPoints} points.",
                          cta: "Unlock once with points",
                          icon: Icons.lock_open,
                          busy: _busy,
                          onTap: _buyOneTimeUnlock,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: cs.outline.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Cards on file",
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "Enter card details only in secure payment-provider checkout. Prox does not accept manually entered payment tokens.",
                            ),
                            const SizedBox(height: 12),
                            if (_cardsOnFile.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              RadioGroup<String>(
                                groupValue: _selectedPaymentMethodId,
                                onChanged: (String? value) {
                                  if (_busy ||
                                      value == null ||
                                      value.trim().isEmpty)
                                    return;
                                  _selectDefaultCard(value);
                                },
                                child: Column(
                                  children: _cardsOnFile
                                      .map((card) {
                                        final pmId =
                                            (card["paymentMethodId"] ?? "")
                                                .trim();
                                        final selected =
                                            pmId.isNotEmpty &&
                                            pmId == _selectedPaymentMethodId;
                                        return RadioListTile<String>(
                                          value: pmId,
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(_cardSummary(card)),
                                          subtitle: Text(
                                            selected
                                                ? "Selected for checkout"
                                                : "Tap to select",
                                          ),
                                        );
                                      })
                                      .toList(growable: false),
                                ),
                              ),
                              const SizedBox(height: 10),
                              const ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text("Prepaid access"),
                                subtitle: Text(
                                  "Each purchase provides 30 days. Automatic renewal is not enabled.",
                                ),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                initialValue: _paymentMode,
                                decoration: const InputDecoration(
                                  labelText: "Payment mode",
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: MonetizationService
                                        .paymentModePointsOnly,
                                    child: Text("Points only"),
                                  ),
                                  DropdownMenuItem(
                                    value:
                                        MonetizationService.paymentModeCashOnly,
                                    child: Text("Cash only"),
                                  ),
                                  DropdownMenuItem(
                                    value: MonetizationService
                                        .paymentModePointsFirst,
                                    child: Text("Points first"),
                                  ),
                                ],
                                onChanged: _busy
                                    ? null
                                    : (value) async {
                                        if (value == null) return;
                                        setState(() => _paymentMode = value);
                                        await _saveBillingPreferences();
                                      },
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : () =>
                                                _startExternalCheckoutWithSavedCard(
                                                  "biz_monthly_subscription",
                                                  "30-day access",
                                                ),
                                      icon: const Icon(
                                        Icons.autorenew_outlined,
                                      ),
                                      label: const Text(
                                        "Use saved card: 30 days",
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : () =>
                                                _startExternalCheckoutWithSavedCard(
                                                  "biz_onetime_unlock",
                                                  "one-time unlock",
                                                ),
                                      icon: const Icon(
                                        Icons.lock_open_outlined,
                                      ),
                                      label: const Text(
                                        "Use saved card: one-time",
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : _openBuyOnePoint,
                                      icon: const Icon(Icons.stars_outlined),
                                      label: const Text(
                                        "Buy 1 Prox Point (\$0.01)",
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _PayOptionCard(
                        title: "Card checkout (30 days)",
                        subtitle:
                            "Opens checkout for one prepaid 30-day period. Payment must be confirmed before access is enabled.",
                        cta: "Start 30-day card checkout",
                        icon: Icons.credit_score_outlined,
                        busy: _busy,
                        onTap: () => _startExternalCheckout(
                          "biz_monthly_subscription",
                          "30-day access",
                        ),
                      ),
                      const SizedBox(height: 10),
                      _PayOptionCard(
                        title: "Card checkout (beta scaffold)",
                        subtitle:
                            "Creates an external checkout intent for provider handoff. Final card processor wiring is pending.",
                        cta: "Prepare one-time card checkout",
                        icon: Icons.credit_card_outlined,
                        busy: _busy,
                        onTap: () => _startExternalCheckout(
                          "biz_onetime_unlock",
                          "one-time unlock",
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: cs.primary.withValues(alpha: 0.30),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Activation path",
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.primary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "When a user is ready to activate, this screen completes a real entitlement transaction against Firestore using Prox Points.",
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            if (_unlocked) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : _activateBusinessRoiNow,
                                  icon: const Icon(
                                    Icons.rocket_launch_outlined,
                                  ),
                                  label: const Text("Start ROI matching now"),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        "Billing controls",
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _load,
                              icon: const Icon(Icons.cancel_outlined),
                              label: const Text("Refresh access status"),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const FeatureExampleScreen(),
                                      ),
                                    ),
                              icon: const Icon(Icons.restart_alt),
                              label: const Text("Try a local example"),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text("Done"),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );

    // Tutorial overlay keeps Prox logo always tappable.
    return TutorialOverlayHost(
      logoTopPadding: 8,
      logoLeftPadding: 12,
      child: scaffold,
    );
  }
}

class _PayOptionCard extends StatelessWidget {
  const _PayOptionCard({
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.icon,
    required this.busy,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String cta;
  final IconData icon;
  final bool busy;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: busy ? null : () async => onTap(),
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(cta),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
