import 'package:flutter/material.dart';
import 'package:prox/widgets/progress_checklist_screen.dart';

class MissingSweepCheckScreen extends StatelessWidget {
  const MissingSweepCheckScreen({super.key});
  @override
  Widget build(BuildContext context) => const ProgressChecklistScreen(
    title: 'Feature sweep',
    storageKey: 'feature_sweep',
    introduction:
        'Check that each visible feature offers a complete action or a clearly labeled useful example.',
    steps: [
      (
        title: 'Visit every home tab',
        detail:
            'Open each tab, wait for loading to finish, then try its primary action.',
      ),
      (
        title: 'Open every Settings destination',
        detail:
            'Check help, privacy, sound, match settings, reports, support, and account controls.',
      ),
      (
        title: 'Try empty and error states',
        detail:
            'Use an account without history and repeat while offline. Verify explanatory text and retry actions.',
      ),
      (
        title: 'Inspect gated features',
        detail:
            'Confirm the reason for restricted access is readable and any example is explicitly labeled.',
      ),
      (
        title: 'Try every store example',
        detail:
            'Verify examples can be interacted with and do not spend points or change live entitlements.',
      ),
      (
        title: 'Report a reproducible problem',
        detail:
            'Copy this checklist and include exact navigation steps in a bug report.',
      ),
    ],
  );
}
