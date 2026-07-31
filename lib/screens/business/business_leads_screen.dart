import "package:flutter/material.dart";

import "package:prox/screens/match_inbox/match_inbox_screen.dart";
import "package:prox/screens/matches/matches_screen.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/screens/services/match_settings_service.dart";

class BusinessLeadsScreen extends StatelessWidget {
  const BusinessLeadsScreen({super.key});

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

  void _openNearby(BuildContext context) {
    // ignore: discarded_futures
    _pushWithHelpContext(
      context,
      contextKey: "business:live_leads",
      page: const MatchInboxScreen(),
    );
  }

  void _openMatches(BuildContext context) {
    // ignore: discarded_futures
    _pushWithHelpContext(
      context,
      contextKey: "business:active_chats",
      page: const MatchesScreen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget card(Widget child) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
          ),
          child: child,
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Leads"),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Lead filters", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                StreamBuilder(
                  stream: MatchSettingsService.instance.watchDiscovery(),
                  builder: (context, snap) {
                    final settings = MatchSettingsService.instance.current;
                    return Column(
                      children: [
                        SwitchListTile.adaptive(
                          value: settings.businessOnly,
                          onChanged: MatchSettingsService.instance.setBusinessOnly,
                          title: const Text("Business-only"),
                          subtitle: const Text("Show clients looking for providers."),
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile.adaptive(
                          value: settings.immediateOnly,
                          onChanged: MatchSettingsService.instance.setImmediateOnly,
                          title: const Text("Immediate-only"),
                          subtitle: const Text("Only show people who need help now."),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Quick actions", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => _openNearby(context),
                  icon: const Icon(Icons.radar_outlined),
                  label: const Text("Open live leads"),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _openMatches(context),
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text("Open active chats"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
