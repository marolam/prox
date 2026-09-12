import 'package:flutter/material.dart';
import 'package:prox/widgets/progress_checklist_screen.dart';
import 'checklist_content.dart';

class ReleaseCandidateChecklistScreen extends StatelessWidget {
  const ReleaseCandidateChecklistScreen({super.key});
  @override
  Widget build(BuildContext context) => const ProgressChecklistScreen(
    title: 'Release checklist',
    storageKey: 'release_candidate',
    introduction:
        'Repeat these checks on both Android and iOS for each candidate build. Reset progress before testing a new candidate.',
    steps: releaseReviewSteps,
  );
}
