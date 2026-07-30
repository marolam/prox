// lib/screens/support/support_center_screen.dart
//
// Tester-facing support hub. Gives early users a clear place to report bugs,
// request help, or share ideas. Drafts are kept locally so they can jot
// notes even if they lose connection mid-session.

import "package:flutter/material.dart";
import "package:url_launcher/url_launcher.dart";

import "package:prox/models/support_ticket_draft.dart";
import "package:prox/screens/support/support_compose_screen.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/support_ticket_queue.dart";
import "package:prox/widgets/retry_banner.dart";
import "package:prox/widgets/safe_snack.dart";

class SupportCenterScreen extends StatelessWidget {
  const SupportCenterScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final queue = SupportTicketQueue.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Support & feedback"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            "Help us shape Prox",
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "This is the tester support hub. If you run into a bug, something feels confusing, or you have an idea that would make Prox better, send it here.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          const _SupportHintCard(),
          const SizedBox(height: 16),
          const RetryBanner(
            message:
                "If your connection drops, anything you draft here stays on this device until you send or delete it.",
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () {
              // ignore: discarded_futures
              _pushWithHelpContext(
                context,
                contextKey: "support:compose_message",
                page: const SupportComposeScreen(),
              );
            },
            icon: const Icon(Icons.edit_note),
            label: const Text("Write a support message"),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _openTesterForm(context),
            icon: const Icon(Icons.bug_report_outlined),
            label: const Text("Open tester support form"),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _emailSupport(context),
            icon: const Icon(Icons.email_outlined),
            label: const Text("Email support"),
          ),
          const SizedBox(height: 24),
          Text(
            "Saved drafts on this device",
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: queue,
            builder: (context, _) {
              final drafts = queue.drafts;
              if (drafts.isEmpty) {
                return Text(
                  "No drafts yet. Start a support message and it will appear here until you send or delete it.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                );
              }

              return Column(
                children: drafts
                    .map(
                      (d) => _DraftTile(
                        draft: d,
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            "What to include (if you can)",
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const _Bullet(
            text:
                "What you were trying to do (e.g. starting a meetup, opening matches).",
          ),
          const _Bullet(
            text:
                "What happened instead (error message, strange behavior, or nothing).",
          ),
          const _Bullet(
            text:
                "Rough time it happened and which phone you\u2019re using (Android/iOS, model).",
          ),
          const _Bullet(
            text:
                "Screenshots if it helps (especially for layout glitches or visual bugs).",
          ),
          const SizedBox(height: 24),
          Text(
            "We read every report and use it to tune trust, matches, and the overall experience.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _openTesterForm(BuildContext context) async {
    // Placeholder URL for the tester portal / support form.
    final Uri uri = Uri.parse("https://prox-us.com/tester-support");
    final bool ok =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      if (!context.mounted) return;
      safeShowSnackBar(context, "Could not open the support form.");
    }
  }

  static Future<void> _emailSupport(BuildContext context) async {
    final Uri uri = Uri(
      scheme: "mailto",
      path: "support@prox-us.com",
      query: Uri.encodeQueryComponent(
        "subject=Prox tester feedback&body=What were you trying to do?\nWhat happened instead?\nAny screenshots or extra details?",
      ),
    );

    final bool ok = await launchUrl(uri);
    if (!ok) {
      if (!context.mounted) return;
      safeShowSnackBar(context, "Could not open email app.");
    }
  }
}

class _SupportHintCard extends StatelessWidget {
  const _SupportHintCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: cs.outline.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lightbulb_outline,
              color: cs.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Short, honest feedback beats long essays. A couple of sentences about what felt good or rough is perfect.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "\u2022",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({required this.draft});

  final SupportTicketDraft draft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final queue = SupportTicketQueue.instance;

    final String createdLabel =
        "${draft.createdAt.month.toString().padLeft(2, "0")}/"
        "${draft.createdAt.day.toString().padLeft(2, "0")} "
        "${draft.createdAt.hour.toString().padLeft(2, "0")}:"
        "${draft.createdAt.minute.toString().padLeft(2, "0")}";

    final String snippet = draft.message.length <= 80
        ? draft.message
        : "${draft.message.substring(0, 77)}...";

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: cs.outline.withValues(alpha: 0.35),
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        title: Text(
          draft.subject.isEmpty ? "Untitled support message" : draft.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 2),
            Text(
              snippet,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Draft \u2022 $createdLabel",
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        onTap: () {
          final previous = ContextHelpService.instance.contextKey.value;
          ContextHelpService.instance.setContext("support:draft_edit");
          // ignore: discarded_futures
          Navigator.of(context)
              .push(
                MaterialPageRoute<void>(
                  builder: (_) => SupportComposeScreen(
                    existingDraft: draft,
                  ),
                ),
              )
              .then((_) {
                ContextHelpService.instance.setContext(previous);
              });
        },
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: "Delete draft",
          onPressed: () {
            queue.removeDraft(draft.id);
          },
        ),
      ),
    );
  }
}
