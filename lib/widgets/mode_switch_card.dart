import "package:flutter/material.dart";
import "package:prox/models/user_settings.dart";
import "package:prox/services/user_settings_service.dart";

class ModeSwitchCard extends StatelessWidget {
  const ModeSwitchCard({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = UserSettingsService.instance.current;
    final canUseProMode = UserSettingsService.instance.canUseProModePreview;
    final segments = <ButtonSegment<AppUxMode>>[
      const ButtonSegment<AppUxMode>(
        value: AppUxMode.party,
        icon: Icon(Icons.person_outline),
        label: Text("Personal"),
      ),
      if (canUseProMode)
        const ButtonSegment<AppUxMode>(
          value: AppUxMode.business,
          icon: Icon(Icons.work_outline),
          label: Text("Pro"),
        ),
    ];
    final selectedMode = canUseProMode ? settings.uxMode : AppUxMode.party;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.swap_horiz),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "App mode",
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<AppUxMode>(
                segments: segments,
                selected: <AppUxMode>{selectedMode},
                onSelectionChanged: (selection) {
                  final next = selection.first;
                  if (next == AppUxMode.business && !canUseProMode) return;
                  if (next == settings.uxMode) return;
                  UserSettingsService.instance.setUxMode(next);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        next == AppUxMode.party
                            ? "Switched to Personal Mode."
                            : "Switched to Pro Mode.",
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
