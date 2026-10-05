import 'package:flutter/material.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/services/user_settings_service.dart';
import 'package:prox/widgets/prox_circle_hold.dart';
import 'treasure_compass_panel.dart';

class TreasureHuntScreen extends StatefulWidget {
  const TreasureHuntScreen({super.key});
  @override
  State<TreasureHuntScreen> createState() => _TreasureHuntScreenState();
}

class _TreasureHuntScreenState extends State<TreasureHuntScreen> {
  bool _activated = false;
  double _progress = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Treasure Hunt')),
    body: StreamBuilder<UserSettings>(
      stream: UserSettingsService.instance.watch(),
      builder: (context, snapshot) {
        final discovery =
            (snapshot.data ?? UserSettingsService.instance.current)
                .matchDiscovery;
        if (discovery.modeKind != MatchingModeKind.treasureHunt) {
          return const Center(
            child: Text('Choose Treasure Hunt in matching modes to explore.'),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: _activated
                ? TreasureCompassPanel(
                    key: ValueKey(discovery),
                    discovery: discovery,
                  )
                : Column(
                    children: [
                      const Text(
                        'Hold the Prox Circle for 3 Seconds to Activate Matching Compass',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ProxCircleHold(
                        onHold: () => setState(() => _activated = true),
                        onProgress: (value) =>
                            setState(() => _progress = value),
                        child: SizedBox(
                          width: 196,
                          height: 196,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned.fill(
                                child: CircularProgressIndicator(
                                  value: _progress,
                                  strokeWidth: 6,
                                ),
                              ),
                              const Icon(Icons.explore, size: 90),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    ),
  );
}
