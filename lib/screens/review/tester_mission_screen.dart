import 'package:flutter/material.dart';
import 'package:prox/widgets/progress_checklist_screen.dart';
import 'checklist_content.dart';

class TesterMissionScreen extends StatelessWidget {
  const TesterMissionScreen({super.key});
  @override
  Widget build(BuildContext context) => const ProgressChecklistScreen(
    title: 'Tester mission',
    storageKey: 'tester_mission',
    introduction:
        'Try the complete Prox journey with another consenting tester. These steps help you find and report problems consistently.',
    steps: testerMissionSteps,
  );
}
