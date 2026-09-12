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
/// - Party scope (All / Extended / Direct)
class DiscoverySettingsScreen extends StatelessWidget {
  const DiscoverySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final matchSettings = MatchSettingsService.instance;
    final userSettings = UserSettingsService.instance;

    return Scaffold(
      appBar: AppBar(title: const Text("Discovery settings")),
      body: StreamBuilder<MatchDiscoverySettings>(
        stream: matchSettings.watchDiscovery(),
        initialData: matchSettings.current,
        builder: (context, snap) {
          final settings = snap.data ?? matchSettings.current;

          final radius = settings.radiusMiles;
          final businessOnly = settings.businessOnly;
          final immediateOnly = settings.immediateOnly;
          final scope = settings.partyScope;
          final ageBracket = settings.ageBracket;

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
              Text("Party scope", style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  MatchFilterChip(
                    label: "All nearby",
                    selected: scope == MatchPartyScope.all,
                    onTap: () =>
                        matchSettings.setPartyScope(MatchPartyScope.all),
                  ),
                  MatchFilterChip(
                    label: "Extended party",
                    selected: scope == MatchPartyScope.extendedOnly,
                    onTap: () => matchSettings.setPartyScope(
                      MatchPartyScope.extendedOnly,
                    ),
                  ),
                  MatchFilterChip(
                    label: "Direct party",
                    selected: scope == MatchPartyScope.partyOnly,
                    onTap: () =>
                        matchSettings.setPartyScope(MatchPartyScope.partyOnly),
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
              Text("Age preference", style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: MatchAgeBracket.values
                    .map(
                      (bracket) => MatchFilterChip(
                        label: bracket.label,
                        selected: ageBracket == bracket,
                        onTap: () => matchSettings.setAgeBracket(bracket),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 10),
              Text(
                "Use this to narrow Nearby results to a preferred age bracket. "
                "Profiles without age data are excluded when a bracket is selected.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 24),
              Text("Business Mode filters", style: theme.textTheme.titleMedium),
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
                "Get help with discovery",
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                "Open Support & feedback for help with these filters. The User's Guide includes a walkthrough, and Tester tools includes an isolated discovery simulator to practice with example profiles.",
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
