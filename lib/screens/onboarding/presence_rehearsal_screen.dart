import 'package:flutter/material.dart';
import 'package:prox/widgets/progress_checklist_screen.dart';
import 'package:prox/screens/review/checklist_content.dart';

class PresenceRehearsalScreen extends StatelessWidget {
  const PresenceRehearsalScreen({super.key, required this.uid});
  final String uid;
  @override
  Widget build(BuildContext context) => ProgressChecklistScreen(
    title: 'Presence rehearsal',
    storageKey: 'presence.$uid',
    introduction:
        'Get comfortable with discovery before arranging your first meetup.',
    steps: presenceRehearsalSteps,
  );
}
