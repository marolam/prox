import "package:flutter/material.dart";

enum LocationExplainerMode { introduction, permissionPromptContext }

class LocationPermissionExplainerScreen extends StatelessWidget {
  const LocationPermissionExplainerScreen({
    super.key,
    this.mode = LocationExplainerMode.introduction,
    required this.onContinue,
    required this.onSkip,
  });

  final LocationExplainerMode mode;
  final Future<void> Function() onContinue;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text("Location permission")),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Prox uses location for nearby discovery."),
              const SizedBox(height: 16),
              FilledButton(onPressed: onContinue, child: const Text("Continue")),
              TextButton(onPressed: onSkip, child: const Text("Not now")),
            ],
          ),
        ),
      );
}