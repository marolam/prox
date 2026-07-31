import "package:flutter/material.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/services/match_settings_service.dart";
import "package:prox/services/user_settings_service.dart";
import "package:prox/widgets/match_filter_chip.dart";
import "package:prox/widgets/match_radius_slider.dart";
import "package:prox/widgets/onboarding/business_intro_sheet.dart";

/// DiscoverySettingsScreen
///
/// Central place for early testers to adjust how discovery works:
/// - radius
/// - Business Mode filters (All / Business / Immediate)
/// - Party scope (All / Extended / Direct (placeholder))
class DiscoverySettingsScreen extends StatelessWidget {
  const DiscoverySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final matchSettings = MatchSettingsService.instance;
    final userSettings = UserSettingsService.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Discovery settings"),
      ),
      body: StreamBuilder<MatchDiscoverySettings>(
        stream: matchSettings.watchDiscovery(),
        initialData: matchSettings.current,
        builder: (context, snap) {
          final settings = snap.data ?? matchSettings.current;

          final radius = settings.radiusMiles;
          final businessOnly = settings.businessOnly;
          final immediateOnly = settings.immediateOnly;
          final scope = settings.partyScope;

          // One-time intro: first time they arrive here with any Business
          // filter active, show a short explainer sheet.
          final shouldShowIntro =
              !userSettings.current.hasSeenBusinessIntro &&
                  (businessOnly || immediateOnly);

          if (shouldShowIntro) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!context.mounted) return;
              await BusinessIntroSheet.show(context);
              userSettings.markBusinessIntroSeen();
            });
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                "Nearby discovery",
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "These options control who appears in your Nearby list. "
                "Business filters apply on top of your radius and Party settings.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              MatchRadiusSlider(
                value: radius,
                onChanged: (value) {
                  matchSettings.setRadiusMiles(value);
                },
              ),

              const SizedBox(height: 18),
              Text(
                "Party scope",
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  MatchFilterChip(
                    label: "All nearby",
                    selected: scope == MatchPartyScope.all,
                    onTap: () => matchSettings.setPartyScope(MatchPartyScope.all),
                  ),
                  MatchFilterChip(
                    label: "Extended party",
                    selected: scope == MatchPartyScope.extendedOnly,
                    onTap: () => matchSettings.setPartyScope(MatchPartyScope.extendedOnly),
                  ),
                  MatchFilterChip(
                    label: "Direct party (soon)",
                    selected: scope == MatchPartyScope.partyOnly,
                    onTap: () => matchSettings.setPartyScope(MatchPartyScope.partyOnly),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                "Extended party narrows discovery to your tester network (same root referrer). "
                "Direct party is a future upgrade that will only show people you're directly connected to in Party.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 24),
              Text(
                "Business Mode filters",
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  MatchFilterChip(
                    label: "All users",
                    selected: !businessOnly,
                    onTap: () {
                      matchSettings.setBusinessOnly(false);
                      matchSettings.setImmediateOnly(false);
                    },
                  ),
                  MatchFilterChip(
                    label: "Business only",
                    selected: businessOnly && !immediateOnly,
                    onTap: () {
                      matchSettings.setBusinessOnly(true);
                      matchSettings.setImmediateOnly(false);
                    },
                  ),
                  MatchFilterChip(
                    label: "Immediate",
                    selected: businessOnly && immediateOnly,
                    onTap: () {
                      matchSettings.setImmediateOnly(
                        !(businessOnly && immediateOnly),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                "Immediate shows only Business Mode users who set their availability "
                "to \"Immediate\". Business-only shows any Business Mode providers "
                "within your radius regardless of their specific window.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Support helpers (coming soon)",
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                "A future update will let some users opt into Support Mode, where they can "
                "volunteer to help others with questions or issues and earn Prox Points. "
                "Support Mode will work alongside these discovery filters so helpers are easy to find when you need them.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
