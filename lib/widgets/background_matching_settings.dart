import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:prox/services/matching/background_matching_service.dart';

class BackgroundMatchingSettings extends StatefulWidget {
  const BackgroundMatchingSettings({super.key});
  @override
  State<BackgroundMatchingSettings> createState() =>
      _BackgroundMatchingSettingsState();
}

class _BackgroundMatchingSettingsState
    extends State<BackgroundMatchingSettings> {
  final service = BackgroundMatchingService.instance;
  @override
  void initState() {
    super.initState();
    service.start();
  }

  Future<void> _toggle(bool enabled) async {
    if (enabled) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Keep matching in the background?'),
          content: const Text(
            'Prox collects and uploads approximate location even when the app is closed to find nearby connections. It keeps only your latest area, not a route history. Significant alerts require at least two keyword matches in each direction. Android shows a quiet ongoing notification. You can stop this here or by turning location or matching off.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      final granted = await service.requestLocationAccess();
      if (!mounted) return;
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Choose Allow all the time / Always for Prox location in phone settings.',
            ),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: openAppSettings,
            ),
          ),
        );
        return;
      }
    }
    await service.update(service.preferences.copyWith(enabled: enabled));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      if (!BackgroundMatchingService.available) return const SizedBox.shrink();
      final preferences = service.preferences;
      return Column(
        children: [
          SwitchListTile(
            title: const Text('Continuous background matching'),
            subtitle: Text(
              service.supported
                  ? service.status
                  : 'Available on Android and iPhone.',
            ),
            value: preferences.enabled,
            onChanged: service.supported && !service.busy ? _toggle : null,
          ),
          ListTile(
            title: const Text('Significant-match alerts per day'),
            subtitle: const Text(
              'At least 2 keyword matches in each direction. At least 4 hours between alerts; the same person at most once every 7 days.',
            ),
            trailing: DropdownButton<int>(
              value: preferences.dailyAlertLimit,
              items: const [
                DropdownMenuItem(value: 1, child: Text('1')),
                DropdownMenuItem(value: 3, child: Text('3')),
                DropdownMenuItem(value: 6, child: Text('6')),
              ],
              onChanged: service.busy
                  ? null
                  : (value) {
                      if (value != null)
                        service.update(
                          preferences.copyWith(dailyAlertLimit: value),
                        );
                    },
            ),
          ),
          SwitchListTile(
            title: const Text('Quiet hours'),
            subtitle: const Text(
              'No significant-match alerts from 10 PM to 8 AM, local time.',
            ),
            value: preferences.quietHoursEnabled,
            onChanged: service.busy
                ? null
                : (value) => service.update(
                    preferences.copyWith(quietHoursEnabled: value),
                  ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Ordinary background opportunities stay quiet. Phone power-saving settings, connectivity, force-stop and location permissions can pause updates. An alert is an opportunity, not a guaranteed meeting.',
            ),
          ),
          const Divider(height: 28),
        ],
      );
    },
  );
}
