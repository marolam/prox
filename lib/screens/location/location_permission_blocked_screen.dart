import "package:flutter/material.dart";

class LocationPermissionBlockedScreen extends StatelessWidget {
  const LocationPermissionBlockedScreen({super.key, required this.onRetry, required this.onRecheck});

  final Future<void> Function() onRetry;
  final Future<void> Function() onRecheck;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text("Location blocked")),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Location permission is needed for Nearby."),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text("Retry")),
              TextButton(onPressed: onRecheck, child: const Text("Recheck")),
            ],
          ),
        ),
      );
}