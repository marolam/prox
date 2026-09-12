import 'package:flutter/material.dart';
import 'package:prox/widgets/progress_checklist_screen.dart';
import 'checklist_content.dart';

class AppReviewSurvivalKitScreen extends StatelessWidget {
  const AppReviewSurvivalKitScreen({super.key});
  @override
  Widget build(BuildContext context) => const ProgressChecklistScreen(
    title: 'App Review guide',
    storageKey: 'app_review',
    introduction:
        'Use a dedicated reviewer account supplied through the store review process. Start with the core journey below. The User’s Guide includes a walkthrough for when no nearby tester is online. Pro examples do not activate paid features.',
    steps: testerMissionSteps,
  );
}
