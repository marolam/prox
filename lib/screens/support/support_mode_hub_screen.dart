import "package:flutter/material.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/progression_service.dart";
import "package:prox/services/support_mode_service.dart";
import "package:prox/screens/support/technician_dashboard.dart";

class SupportModeHubScreen extends StatelessWidget {
  const SupportModeHubScreen({super.key});

  Future<void> _pushWithHelpContext(
    BuildContext context, {
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

  Future<void> _showTerms(BuildContext context) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.support_agent_outlined, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Support Mode terms (v1)",
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  "Support Mode is opt-in. Helpers must be respectful, evidence-based, and honest.\n\n"
                  " Help users troubleshoot + learn Prox\n"
                  " Escalate safety/fraud/illegal concerns\n"
                  " Never harass, shame, or pressure users\n\n"
                  "Abuse of Support Mode can lead to suspension.\n\n"
                  "This is a tester scaffold - live queue + auditing comes next.",
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.25),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      await SupportModeService.instance.acceptTerms();
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                    child: const Text("I understand & accept"),
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

    if (uid.isEmpty) {
      return const Scaffold(
        body: Center(child: Text("Sign in to use Support Mode")),
      );
    }

    // ignore: discarded_futures
    SupportModeService.instance.ensureLoaded();

    return Scaffold(
      appBar: AppBar(title: const Text("Support Mode")),
      body: FutureBuilder<ProgressionSnapshot?>(
        future: ProgressionService.instance.loadForUser(uid),
        builder: (context, snap) {
          final progression = snap.data;
          final bool supportUnlocked = progression?.has(ProxFeatureUnlock.supportMode) ?? false;
          final bool techUnlocked = progression?.has(ProxFeatureUnlock.supportTechnician) ?? false;
          final String supportReason = progression == null
              ? "Loading progression..."
              : ProgressionService.instance.lockedReason(
                  feature: ProxFeatureUnlock.supportMode,
                  snapshot: progression,
                );
          final String techReason = progression == null
              ? "Loading progression..."
              : ProgressionService.instance.lockedReason(
                  feature: ProxFeatureUnlock.supportTechnician,
                  snapshot: progression,
                );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Community-powered support", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                  "Opt-in helper mode for testers. Next: live queue position + routing + audits.",
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.25),
                ),
                if (!supportUnlocked) ...[
                  const SizedBox(height: 8),
                  Text(
                    "Locked: $supportReason",
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: SupportModeService.instance,
            builder: (context, _) {
              final s = SupportModeService.instance;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.toggle_on_outlined, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Enable Support Mode", style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text(
                            s.enabled ? "Enabled on this device." : "Off.",
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: supportUnlocked && s.enabled,
                      onChanged: (v) async {
                        if (!supportUnlocked) return;
                        if (!s.termsAccepted) {
                          await _showTerms(context);
                        }
                        if (!SupportModeService.instance.termsAccepted) return;
                        await SupportModeService.instance.setEnabled(v);
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showTerms(context),
              icon: const Icon(Icons.rule_outlined),
              label: const Text("View terms"),
            ),
          ),
          const SizedBox(height: 10),
          AnimatedBuilder(
            animation: SupportModeService.instance,
            builder: (context, _) {
              final enabled = SupportModeService.instance.enabled;
              return SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (enabled && techUnlocked)
                      ? () {
                          // ignore: discarded_futures
                          _pushWithHelpContext(
                            context,
                            contextKey: "support:technician_dashboard",
                            page: const TechnicianDashboardScreen(),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.view_kanban_outlined),
                  label: const Text("Open Technician Dashboard"),
                ),
              );
            },
          ),
          if (!techUnlocked) ...[
            const SizedBox(height: 8),
            Text(
              "Technician dashboard locked: $techReason",
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ],
          );
        },
      ),
    );
  }
}