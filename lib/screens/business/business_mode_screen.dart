import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "package:prox/screens/business/business_mode_setup_screen.dart";
import "package:prox/screens/settings/account/buy_points_screen.dart";
import "package:prox/screens/settings/account/payment_methods_screen.dart";
import "package:prox/services/business_mode/business_mode_eligibility.dart";
import "package:prox/services/business_mode/business_mode_state_service.dart";
import "package:prox/services/business_mode_service.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/monetization_service.dart";
import "package:prox/services/points_service.dart";
import "package:prox/release/release_flags.dart";
import "package:prox/widgets/business_mode_gate.dart";

class BusinessModeScreen extends StatefulWidget {
  const BusinessModeScreen({super.key});

  @override
  State<BusinessModeScreen> createState() => _BusinessModeScreenState();
}

class _BusinessModeScreenState extends State<BusinessModeScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    BusinessModeService.instance.loadBusinessData();
  }

  Future<void> _openSetup() async {
    final previous = ContextHelpService.instance.contextKey.value;
    ContextHelpService.instance.setContext("business:mode_setup");
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BusinessModeSetupScreen()),
    );
    ContextHelpService.instance.setContext(previous);
    // ignore: discarded_futures
    BusinessModeService.instance.loadBusinessData();
    if (mounted) setState(() {});
  }

  Future<void> _toggleActive(String uid, bool active) async {
    await BusinessModeStateService.instance.setActive(uid, active);
    if (mounted) setState(() {});
  }

  Future<void> _subscribeBusiness(String uid) async {
    if (_busy) return;
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
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Business Mode unlocked locally for tester flow.")),
        );
        return;
      }

      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Not enough points to activate Business Mode.")),
        );
        return;
      }

      await BusinessModeStateService.instance.setActive(uid, true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Business Mode activated.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not activate Business Mode: $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.trim().isEmpty) {
      return const Scaffold(body: Center(child: Text("Not signed in")));
    }

    Widget card(Widget child) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
          ),
          child: child,
        );

    return Scaffold(
      appBar: AppBar(title: const Text("Business Mode")),
      body: StreamBuilder<PointsMeta>(
        stream: PointsService.instance.watchMeta(uid),
        builder: (context, snap) {
          final meta = snap.data ?? PointsService.instance.peekMeta(uid);
          return FutureBuilder<BusinessGateState>(
            future: BusinessModeEligibility.gateForUser(uid: uid, meta: meta),
            builder: (context, gateSnap) {
              final gate = gateSnap.data ?? BusinessModeEligibility.gateFromMeta(meta);
              final eligible = gate == BusinessGateState.eligible || gate == BusinessGateState.active;

              return AnimatedBuilder(
            animation: BusinessModeService.instance,
            builder: (context, _) {
              final service = BusinessModeService.instance;
              final profile = service.profile;
              final sub = service.subscription;

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Status",
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          eligible
                              ? "Eligible for Business Mode."
                              : "Not eligible yet. Earn trust, points, and meetups to unlock.",
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                "Active",
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            FutureBuilder<bool>(
                              future: BusinessModeStateService.instance.isActive(uid),
                              builder: (context, activeSnap) {
                                final active = activeSnap.data ?? false;
                                return Switch(
                                  value: active,
                                  onChanged: eligible ? (v) => _toggleActive(uid, v) : null,
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Business profile",
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        if (profile == null) ...[
                          Text(
                            "No business profile yet.",
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _openSetup,
                              child: const Text("Start setup"),
                            ),
                          ),
                        ] else ...[
                          Text(
                            profile.businessName,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          if ((profile.businessCategory ?? "").trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              profile.businessCategory!,
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                          if ((profile.businessDescription ?? "").trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              profile.businessDescription!,
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: _openSetup,
                            child: const Text("Edit setup"),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<bool>(
                    future: (() async {
                      final testerUnlocked = await BusinessModeStateService.instance.isTesterUnlocked(uid);
                      if (testerUnlocked) return true;
                      return MonetizationService.instance.isBusinessUnlocked(uid);
                    })(),
                    builder: (context, unlockSnap) {
                      final unlockedByBilling = unlockSnap.data ?? false;
                      final hasLegacySub = sub != null;
                      final activeSub = unlockedByBilling || hasLegacySub;

                      return card(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Subscription",
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 8),
                            if (!activeSub) ...[
                              Text(
                                "No active subscription.",
                                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: () {
                                    if (!eligible) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            "Not eligible yet. Complete setup, add payment method, and top up points.",
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    _subscribeBusiness(uid);
                                  },
                                  child: Text(_busy ? "Activating..." : "Activate Business Mode"),
                                ),
                              ),
                            ] else ...[
                              Text(
                                unlockedByBilling
                                    ? "Business subscription active (billing)"
                                    : "${sub?.tier.displayName ?? "Business"} active",
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              if (!unlockedByBilling && sub?.renewalDate != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  "Renews in ${sub!.daysUntilRenewal} days",
                                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => const PaymentMethodsScreen(),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.credit_card_outlined),
                                      label: const Text("Payment methods"),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => const BuyPointsScreen(),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.stars_outlined),
                                      label: const Text("Buy points"),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ],
              );
            },
              );
            },
          );
        },
      ),
    );
  }
}
