import 'package:flutter/material.dart';
import 'package:prox/widgets/progress_checklist_screen.dart';
import 'checklist_content.dart';
import 'package:prox/screens/review/growth_hub_screen.dart';

class TesterMissionScreen extends StatelessWidget {
  const TesterMissionScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tester mission')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const GrowthReferralEntry(),
        const SizedBox(height: 16),
        const Text(
          'Use the founding tester mission for verified 48-hour progress. '
          'The full checklist below helps you test the Big 5 and recovery paths.',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ProgressChecklistScreen(
                title: 'Tester mission',
                storageKey: 'tester_mission',
                introduction:
                    'Try the complete Prox journey with another consenting tester. These steps help you find and report problems consistently.',
                steps: testerMissionSteps,
              ),
            ),
          ),
          icon: const Icon(Icons.checklist),
          label: const Text('Open full tester checklist'),
        ),
      ],
    ),
  );
}
