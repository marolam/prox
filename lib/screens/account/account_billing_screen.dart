import "package:firebase_auth/firebase_auth.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter/material.dart";

import "package:prox/screens/business/business_mode_screen.dart";
import "package:prox/services/business_mode/business_mode_eligibility.dart";
import "package:prox/services/business_mode/business_mode_state_service.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/monetization_entry_service.dart";
import "package:prox/services/monetization_service.dart";
import "package:prox/services/points_service.dart";
import "package:prox/services/ui_telemetry_service.dart";
import "package:prox/widgets/business_mode_gate.dart";

class AccountBillingScreen extends StatefulWidget {
  const AccountBillingScreen({super.key});

  @override
  State<AccountBillingScreen> createState() => _AccountBillingScreenState();
}

class _AccountBillingScreenState extends State<AccountBillingScreen> {
  Future<void> _pushWithHelpContext({
    required String contextKey,
    required Widget page,
  }) async {
    final previous = ContextHelpService.instance.contextKey.value;
    ContextHelpService.instance.setContext(contextKey);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    ContextHelpService.instance.setContext(previous);
  }

  @override
  void initState() {
    super.initState();
    UiTelemetryService.instance.log(
      "billing_screen_opened",
      meta: {"source": "account"},
    );
  }

  Future<void> _setActive(
    BuildContext context,
    String uid,
    bool active,
  ) async {
    if (active) {
      final paid = await MonetizationService.instance.isBusinessUnlocked(uid);
      if (!paid) {
        if (context.mounted) {
          await MonetizationEntryService.instance.openBusinessPaywall(context);
        }
        return;
      }
    }

    await BusinessModeStateService.instance.setActive(uid, active);
    UiTelemetryService.instance.log(
      active ? "business_mode_activated" : "business_mode_deactivated",
      meta: {"source": "account"},
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openBillingHistory(BuildContext context, String uid) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final stream = FirebaseFirestore.instance
            .collection("users")
            .doc(uid)
            .collection("billing")
            .doc("invoices")
            .collection("items")
            .orderBy("createdAt", descending: true)
            .limit(50)
            .snapshots();

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Billing history",
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 360,
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: stream,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snap.data?.docs ??
                          const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                      if (docs.isEmpty) {
                        return Center(
                          child: Text(
                            "No billing events yet.",
                            style: theme.textTheme.bodyMedium,
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final data = docs[index].data();
                          final sku = (data["sku"] ?? "unknown_sku").toString();
                          final amountPoints = (data["amountPoints"] as num?)?.toInt() ?? 0;
                          final paymentMethod = (data["paymentMethod"] ?? "unknown").toString();
                          final status = (data["status"] ?? "unknown").toString();

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  sku,
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "${amountPoints} points  |  $paymentMethod  |  $status",
                                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.trim().isEmpty) {
      return const Scaffold(body: Center(child: Text("Not signed in")));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Account & billing")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          StreamBuilder<PointsMeta>(
            stream: PointsService.instance.watchMeta(uid),
            builder: (context, snap) {
              final m = snap.data ?? PointsService.instance.peekMeta(uid);

              return FutureBuilder<BusinessGateState>(
                future: BusinessModeEligibility.gateForUser(uid: uid, meta: m),
                builder: (context, gsnap) {
                  final gateState = gsnap.data ?? BusinessModeEligibility.gateFromMeta(m);

                  final bool eligibleOrActive =
                      gateState == BusinessGateState.eligible || gateState == BusinessGateState.active;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BusinessModeGate(
                        state: gateState,
                        onLearnMore: () {
                          // ignore: discarded_futures
                          _pushWithHelpContext(
                            contextKey: "account:business_mode_learn_more",
                            page: const BusinessModeScreen(),
                          );
                        },
                      ),

                      if (eligibleOrActive) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.work_outline, color: cs.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  gateState == BusinessGateState.active
                                      ? "Business Mode is active on this account."
                                      : "You're eligible. Activate Business Mode.",
                                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ),
                              Switch(
                                value: gateState == BusinessGateState.active,
                                onChanged: (v) => _setActive(context, uid, v),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 16),
          FutureBuilder<bool>(
            future: MonetizationService.instance.isBusinessUnlocked(uid),
            builder: (context, paidSnap) {
              final paid = paidSnap.data ?? false;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Payments",
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      paid
                          ? "Business entitlement is active on this account."
                          : "Activate Business entitlement with points from the paywall.",
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Pricing:\n"
                      " Monthly: ${MonetizationService.monthlySubscriptionPoints} points\n"
                      " One-time unlock: ${MonetizationService.oneTimeUnlockPoints} points",
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => MonetizationEntryService.instance.openBusinessPaywall(context),
                        icon: const Icon(Icons.payments_outlined),
                        label: Text(paid ? "Manage billing" : "Open billing"),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _openBillingHistory(context, uid),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text("View billing history"),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}