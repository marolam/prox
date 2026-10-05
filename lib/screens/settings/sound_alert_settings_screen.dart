import "package:flutter/material.dart";
import "package:prox/widgets/background_matching_settings.dart";

import "package:prox/services/match_signal_service.dart";
import "package:prox/services/user_settings_service.dart";

class SoundAlertSettingsScreen extends StatelessWidget {
  const SoundAlertSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = UserSettingsService.instance;

    return Scaffold(
      appBar: AppBar(title: const Text("Sound & alerts")),
      body: StreamBuilder(
        stream: service.watch(),
        builder: (context, _) {
          final settings = service.current;
          final soundOn = settings.matchSoundEnabled;
            final highFitPaused = !soundOn && settings.rareMatchSoundEnabled;
          final previewHint = !soundOn
              ? "Enable Match sounds to preview cues."
              : settings.matchSoundVolume <= 0
              ? "Increase in-app sound volume above 0% to preview cues."
              : null;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              const BackgroundMatchingSettings(),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text("Match notifications"),
                subtitle: const Text(
                  "Allow significant-match notifications. Ordinary background matches stay quiet.",
                ),
                value: settings.matchNotificationsEnabled,
                onChanged: service.setMatchNotificationsEnabled,
              ),
              SwitchListTile(
                secondary: Icon(
                  soundOn
                      ? Icons.volume_up_outlined
                      : Icons.volume_off_outlined,
                ),
                title: const Text("Match sounds"),
                subtitle: const Text("Play a short cue for a new match."),
                value: soundOn,
                onChanged: service.setMatchSoundEnabled,
              ),
              ListTile(
                enabled: soundOn,
                leading: const Icon(Icons.tune),
                title: const Text("In-app sound volume"),
                subtitle: Slider(
                  value: settings.matchSoundVolume,
                  divisions: 10,
                  label: "${(settings.matchSoundVolume * 100).round()}%",
                  onChanged: soundOn ? service.setMatchSoundVolume : null,
                ),
                trailing: SizedBox(
                  width: 42,
                  child: Text(
                    "${(settings.matchSoundVolume * 100).round()}%",
                    textAlign: TextAlign.end,
                  ),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.bolt_outlined),
                title: const Text("Significant-match sound"),
                subtitle: Text(
                  !soundOn
                      ? "Turn on Match sounds to use this cue."
                      : "Allow a noticeable cue when multiple keywords match in both directions.",
                ),
                value: settings.rareMatchSoundEnabled,
                onChanged: soundOn ? service.setRareMatchSoundEnabled : null,
              ),
              if (highFitPaused)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    "High-fit cue is paused while Match sounds is off.",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const Divider(height: 28),
              const ListTile(
                leading: Icon(Icons.hearing_outlined),
                title: Text("Preview cues"),
                subtitle: Text("Play each cue at your selected in-app volume."),
              ),
              if (previewHint != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    previewHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: soundOn && settings.matchSoundVolume > 0
                        ? () => MatchSignalService.instance.preview(rare: false)
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text("Standard match"),
                  ),
                  FilledButton.icon(
                    onPressed:
                        soundOn &&
                            settings.rareMatchSoundEnabled &&
                            settings.matchSoundVolume > 0
                        ? () => MatchSignalService.instance.preview(rare: true)
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text("High-fit match"),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const ListTile(
                leading: Icon(Icons.phone_android_outlined),
                title: Text("Phone notification volume"),
                subtitle: Text(
                  "Background notification sounds also follow your phone's notification volume, silent mode, and Prox notification-channel settings.",
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
