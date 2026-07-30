import "dart:math" as math;

import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/screens/settings/account/buy_points_screen.dart";
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
import "package:url_launcher/url_launcher.dart";

class BusinessPaywallScreen extends StatefulWidget {
  const BusinessPaywallScreen({super.key});

  static Future<bool?> open(BuildContext context) {
    if (!RolloutGateService.instance.isBusinessModeEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(RolloutGateService.instance.businessModeDisabledReason),
        ),
      );
      return Future<bool?>.value(false);
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
  bool _busy = false;
  bool _unlocked = false;
  String? _lastSku;
  final TextEditingController _pmId = TextEditingController();
  final TextEditingController _pmBrand = TextEditingController();
  final TextEditingController _pmLast4 = TextEditingController();
  List<Map<String, String>> _cardsOnFile = const <Map<String, String>>[];
  String? _selectedPaymentMethodId;
  bool _autoRenewWithSelectedCard = false;
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
        return math.min(currentPoints, MonetizationService.monthlySubscriptionPoints);
    }
  }

  double _usdChargeForMode(int currentPoints) {
    if (_paymentMode == MonetizationService.paymentModeCashOnly) {
      return MonetizationService.monthlySubscriptionUsd;
    }
    final pointsApplied = _pointsAppliedForMode(currentPoints);
    return MonetizationService.instance.usdRemainderForPoints(pointsApplied);
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

    final pointsApplied = _pointsAppliedForMode(currentPoints);
    final usdCharge = _usdChargeForMode(currentPoints);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Start Business Mode activation?"),
        content: Text(
          "This starts your first month, applies activation billing, unlocks wallet and store access, and enables early Business Mode features.\n\n"
          "Points this cycle: $pointsApplied\n"
          "Card charge this cycle: \$${usdCharge.toStringAsFixed(2)}\n\n"
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

    if (!mounted) return;
    await MonetizationService.instance.setBusinessActivationBundleUnlocked(
      uid: uid,
      unlocked: true,
      sku: "biz_monthly_subscription",
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pmId.dispose();
    _pmBrand.dispose();
    _pmLast4.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
    final selectedPmId =
        (selectedFromCards["paymentMethodId"] ?? savedPmId).trim();

    if (!mounted) return;
    setState(() {
      _unlocked = unlocked;
      _lastSku = lastSku;
      _cardsOnFile = cards;
      _selectedPaymentMethodId = selectedPmId.isEmpty ? null : selectedPmId;
      _autoRenewWithSelectedCard = prefs["autoRenewWithSelectedCard"] == true;
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
      autoRenewWithSelectedCard: _autoRenewWithSelectedCard,
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
      final cards =
          await MonetizationService.instance.listPaymentMethods(uid: uid);
      if (!mounted) return;
      setState(() {
        _cardsOnFile = cards;
        _selectedPaymentMethodId = paymentMethodId;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCardForSubscription() async {
    if (_busy) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final pmId = _pmId.text.trim();
    if (pmId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a payment method token/id first.")),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final brand = _pmBrand.text.trim();
      final last4 = _pmLast4.text.trim();
      await MonetizationService.instance.saveDefaultPaymentMethod(
        uid: uid,
        paymentMethodId: pmId,
        brand: brand,
        last4: last4,
      );

      final cards =
          await MonetizationService.instance.listPaymentMethods(uid: uid);

      if (!mounted) return;
      setState(() {
        _cardsOnFile = cards;
        _selectedPaymentMethodId = pmId;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Card saved to cards on file.")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startExternalCheckoutWithSavedCard(
      String sku, String label) async {
    if (_busy) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final savedPmId = (_selectedPaymentMethodId ?? "").trim();
    if (savedPmId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Add/select a card on file first, then try again.")),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final session =
          await MonetizationService.instance.createExternalCheckoutSession(
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
                  "Saved-card session created for $label. Session: $sessionId")),
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
        final status =
            (session["status"] ?? "").toString().trim().toLowerCase();

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
          await MonetizationService.instance.setBusinessActivationBundleUnlocked(
            uid: cleanUid,
            unlocked: true,
            sku: sku,
          );
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
                content: Text("Payment confirmed. Business Mode is active.")),
          );
          return;
        }

        if (_terminalFailureStatuses.contains(status)) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Payment status: $status.")),
          );
          return;
        }

        await Future<void>.delayed(const Duration(seconds: 3));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Payment is still processing. Check again shortly after the Square webhook syncs."),
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BuyPointsScreen()),
    );
    await _load();
  }

  Future<void> _subscribeWithSelectedMode() async {
    if (_busy) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _saveBillingPreferences();

    if (_paymentMode == MonetizationService.paymentModeCashOnly) {
      await _startExternalCheckoutWithSavedCard(
          "biz_monthly_subscription", "monthly subscription");
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
        "biz_monthly_subscription", "monthly subscription");
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

      if (timedOut && ReleaseFlags.permissiveTesterUX) {
        await BusinessModeStateService.instance.setTesterUnlocked(uid, true);
        await MonetizationService.instance.setBusinessActivationBundleUnlocked(
          uid: uid,
          unlocked: true,
          sku: "biz_onetime_unlock_tester_local",
        );
        if (!mounted) return;
        setState(() {
          _unlocked = true;
          _lastSku = "biz_onetime_unlock_tester_local";
        });
        Navigator.of(context).pop(true);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? e.toString())),
      );
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

      if (timedOut && ReleaseFlags.permissiveTesterUX) {
        await BusinessModeStateService.instance.setTesterUnlocked(uid, true);
        await MonetizationService.instance.setBusinessActivationBundleUnlocked(
          uid: uid,
          unlocked: true,
          sku: "biz_monthly_subscription_tester_local",
        );
        if (!mounted) return;
        setState(() {
          _unlocked = true;
          _lastSku = "biz_monthly_subscription_tester_local";
        });
        Navigator.of(context).pop(true);
        return;
      }

      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Not enough points. Need ${MonetizationService.monthlySubscriptionPoints} points for monthly subscription.",
            ),
          ),
        );
        return;
      }

      await ActionReceiptService.instance.add(
        kind: "payment",
        title: "Business subscription started",
        detail:
            "Monthly subscription activated with points. SKU=biz_monthly_subscription.",
      );

      if (!mounted) return;
      setState(() {
        _unlocked = true;
        _lastSku = "biz_monthly_subscription";
      });

      Navigator.of(context).pop(true);
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelSubscription() async {
    if (_busy) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      await MonetizationService.instance.cancelMonthlySubscription(uid);

      await ActionReceiptService.instance.add(
        kind: "payment",
        title: "Subscription canceled",
        detail: "Subscription marked inactive. SKU=biz_monthly_subscription.",
      );

      final stillUnlocked =
          await MonetizationService.instance.isBusinessUnlocked(uid);
      if (!mounted) return;
      setState(() => _unlocked = stillUnlocked);
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
      final session =
          await MonetizationService.instance.createExternalCheckoutSession(
        uid: uid,
        sku: sku,
      );
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

  Future<void> _resetLocal() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      await MonetizationService.instance.resetForUser(uid);
      await BusinessModeStateService.instance.setTesterUnlocked(uid, false);

      await ActionReceiptService.instance.add(
        kind: "payment",
        title: "Local Business flags reset",
        detail:
            "Local monetization flags cleared for this account (tester control).",
      );

      if (!mounted) return;
      setState(() {
        _unlocked = false;
        _lastSku = null;
      });
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

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text("Business Mode"),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
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
              final referralsNeeded =
                MonetizationService.instance.referralsNeededForPointsGap(pointsGap);
              final supportNeeded =
                MonetizationService.instance.supportTicketsNeededForPointsGap(pointsGap);

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: cs.outline.withValues(alpha: 0.30)),
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
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
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
                                  style: theme.textTheme.labelSmall?.copyWith(
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
                      border: Border.all(color: cs.outline.withValues(alpha: 0.28)),
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
                          "Price: \$${MonetizationService.monthlySubscriptionUsd.toStringAsFixed(2)} or ${MonetizationService.monthlySubscriptionPoints} points / month",
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
                          "To fully cover next month with points only: $pointsGap additional points",
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
                          "When eligible milestones are complete, first-month activation should be point-funded.",
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
                            label: const Text("Begin activation and free-month start"),
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
                    title: "Monthly subscription (selected payment mode)",
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
                        "Monthly subscription\n\nActivates Business Mode for 30 days using Prox Points.",
                    child: _PayOptionCard(
                      title: "Monthly subscription",
                      subtitle:
                          "Best for active providers. Renews every 30 days. Cost: ${MonetizationService.monthlySubscriptionPoints} points or \$${MonetizationService.monthlySubscriptionUsd.toStringAsFixed(2)}.",
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
                      border:
                          Border.all(color: cs.outline.withValues(alpha: 0.28)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Cards on file",
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _pmId,
                          decoration: const InputDecoration(
                            labelText: "Card method token/id",
                            hintText: "Example: pm_test_123",
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _pmBrand,
                                decoration: const InputDecoration(
                                  labelText: "Brand (optional)",
                                  hintText: "visa",
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _pmLast4,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: "Last 4 (optional)",
                                  hintText: "4242",
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed:
                                    _busy ? null : _saveCardForSubscription,
                                icon: const Icon(Icons.save_outlined),
                                label: const Text("Add card to file"),
                              ),
                            ),
                          ],
                        ),
                        if (_cardsOnFile.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          RadioGroup<String>(
                            groupValue: _selectedPaymentMethodId,
                            onChanged: (String? value) {
                              if (_busy ||
                                  value == null ||
                                  value.trim().isEmpty) return;
                              _selectDefaultCard(value);
                            },
                            child: Column(
                              children: _cardsOnFile.map((card) {
                                final pmId =
                                    (card["paymentMethodId"] ?? "").trim();
                                final selected = pmId.isNotEmpty &&
                                    pmId == _selectedPaymentMethodId;
                                return RadioListTile<String>(
                                  value: pmId,
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(_cardSummary(card)),
                                  subtitle: Text(selected
                                      ? "Selected for checkout and auto-renew"
                                      : "Tap to select"),
                                );
                              }).toList(growable: false),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SwitchListTile.adaptive(
                            value: _autoRenewWithSelectedCard,
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                                "Auto-renew subscription with selected card"),
                            subtitle: const Text(
                                "Stores your preference for monthly renewals."),
                            onChanged: _busy
                                ? null
                                : (value) async {
                                    setState(() =>
                                        _autoRenewWithSelectedCard = value);
                                    await _saveBillingPreferences();
                                  },
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _paymentMode,
                            decoration: const InputDecoration(
                                labelText: "Payment mode"),
                            items: const [
                              DropdownMenuItem(
                                value:
                                    MonetizationService.paymentModePointsOnly,
                                child: Text("Points only"),
                              ),
                              DropdownMenuItem(
                                value: MonetizationService.paymentModeCashOnly,
                                child: Text("Cash only"),
                              ),
                              DropdownMenuItem(
                                value:
                                    MonetizationService.paymentModePointsFirst,
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
                                            "monthly subscription",
                                          ),
                                  icon: const Icon(Icons.autorenew_outlined),
                                  label: const Text("Use saved card: monthly"),
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
                                  icon: const Icon(Icons.lock_open_outlined),
                                  label: const Text("Use saved card: one-time"),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _busy ? null : _openBuyOnePoint,
                                  icon: const Icon(Icons.stars_outlined),
                                  label:
                                      const Text("Buy 1 Prox Point (\$0.01)"),
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
                    title: "Card checkout (monthly)",
                    subtitle:
                        "Creates an external monthly subscription checkout session at production pricing.",
                    cta: "Start monthly card checkout",
                    icon: Icons.credit_score_outlined,
                    busy: _busy,
                    onTap: () => _startExternalCheckout(
                      "biz_monthly_subscription",
                      "monthly subscription",
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
                      border:
                          Border.all(color: cs.primary.withValues(alpha: 0.30)),
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
                              onPressed: _busy ? null : _activateBusinessRoiNow,
                              icon: const Icon(Icons.rocket_launch_outlined),
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
                          onPressed: _busy ? null : _cancelSubscription,
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text("Cancel subscription"),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _resetLocal,
                          icon: const Icon(Icons.restart_alt),
                          label: const Text("Reset billing entitlements"),
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
