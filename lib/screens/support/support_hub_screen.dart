import "package:flutter/material.dart";
import "package:firebase_auth/firebase_auth.dart";

import "package:prox/screens/support/support_center_screen.dart";
import "package:prox/screens/support/support_mode_hub_screen.dart";
import "package:prox/screens/support/user_support_screen.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/progression_service.dart";
import "package:prox/services/ui_telemetry_service.dart";

class SupportHubScreen extends StatelessWidget {
  const SupportHubScreen({super.key});

  Future<void> _pushWithHelpContext(
    BuildContext context, {
    required String contextKey,
    required Widget page,
  }) async {
    ContextHelpService.instance.setContext(contextKey);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    ContextHelpService.instance.setContext("home:support");
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
      appBar: AppBar(title: const Text("Support & feedback")),
      body: FutureBuilder<ProgressionSnapshot?>(
        future: ProgressionService.instance
            .loadForUser(FirebaseAuth.instance.currentUser?.uid ?? ""),
        builder: (context, snap) {
          final progression = snap.data;
          final bool supportUnlocked = progression?.has(ProxFeatureUnlock.supportMode) ?? false;
          final String lockReason = progression == null
              ? "Loading progression..."
              : ProgressionService.instance.lockedReason(
                  feature: ProxFeatureUnlock.supportMode,
                  snapshot: progression,
                );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
          card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Tester Support",
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  "Report bugs, confusion, or safety concerns. Drafts are saved locally.",
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.25),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      UiTelemetryService.instance.log(
                        "support_open",
                        meta: {"source": "support_hub"},
                      );
                      // ignore: discarded_futures
                      _pushWithHelpContext(
                        context,
                        contextKey: "support:support_center",
                        page: const SupportCenterScreen(),
                      );
                    },
                    icon: const Icon(Icons.support_agent_outlined),
                    label: const Text("Open support center"),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      UiTelemetryService.instance.log(
                        "support_ticket_ui_open",
                        meta: {"source": "support_hub"},
                      );
                      // ignore: discarded_futures
                      _pushWithHelpContext(
                        context,
                        contextKey: "support:ticket_dashboard",
                        page: const UserSupportScreen(),
                      );
                    },
                    icon: const Icon(Icons.confirmation_number_outlined),
                    label: const Text("Open ticket dashboard"),
                  ),
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
                  "Support Mode",
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  "Opt-in helper mode for testers who want to assist others.",
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.25),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: supportUnlocked
                        ? () {
                            UiTelemetryService.instance.log(
                              "support_mode_open",
                              meta: {"source": "support_hub"},
                            );
                            // ignore: discarded_futures
                            _pushWithHelpContext(
                              context,
                              contextKey: "support:support_mode",
                              page: const SupportModeHubScreen(),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.support_agent_outlined),
                    label: const Text("Open Support Mode"),
                  ),
                ),
                if (!supportUnlocked) ...[
                  const SizedBox(height: 8),
                  Text(
                    "Locked: $lockReason",
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
          );
        },
      ),
    );
  }
}