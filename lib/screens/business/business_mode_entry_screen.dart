import 'package:flutter/material.dart';
import 'package:prox/services/pro_mode_preview_access.dart';
import 'business_mode_screen.dart';
import 'package:prox/screens/store/feature_example_screen.dart';

class BusinessModeEntryScreen extends StatelessWidget {
  const BusinessModeEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!ProModePreviewAccess.instance.isAllowedForCurrentUser()) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pro Mode')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Live Pro Mode preview is restricted to the approved preview account. You can explore local examples of requests, promotions, and replies.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const FeatureExampleScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Try Pro examples'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const BusinessModeScreen();
  }
}
