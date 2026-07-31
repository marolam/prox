import "package:flutter/material.dart";

import "package:prox/screens/services/match_settings_service.dart";
import "package:prox/models/user_settings.dart";

class BusinessFilterSettingsScreen extends StatelessWidget {
  const BusinessFilterSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final matchSettings = MatchSettingsService.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Filter Settings"),
      ),
      body: StreamBuilder<MatchDiscoverySettings>(
        stream: matchSettings.watchDiscovery(),
        initialData: matchSettings.current,
        builder: (context, snap) {
          final MatchDiscoverySettings settings =
              snap.data ?? matchSettings.current;
          final bool businessOnly = settings.businessOnly;
          final bool hideBusyUsers = settings.immediateOnly;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Text(
                "Show",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              RadioListTile<bool>(
                value: false,
                groupValue: businessOnly,
                title: const Text("All matches"),
                subtitle: const Text("Show all nearby users"),
                onChanged: (_) {
                  matchSettings.setBusinessOnly(false);
                  matchSettings.setImmediateOnly(false);
                },
              ),
              RadioListTile<bool>(
                value: true,
                groupValue: businessOnly,
                title: const Text("Business Mode users only"),
                subtitle: const Text("Only show users currently open for business"),
                onChanged: (_) {
                  matchSettings.setBusinessOnly(true);
                },
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: hideBusyUsers,
                title: const Text("Hide Busy Users"),
                subtitle: const Text(
                  "When enabled, show only business users marked available now",
                ),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: businessOnly
                    ? (v) {
                        matchSettings.setImmediateOnly(v == true);
                      }
                    : null,
              ),
              if (!businessOnly)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 12),
                  child: Text(
                    "Turn on Business Mode users first to use Hide Busy Users.",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
