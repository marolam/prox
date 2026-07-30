import "package:flutter/material.dart";

class LocationIssueBanner extends StatelessWidget {
  const LocationIssueBanner({super.key, this.message, this.hint, this.onRetry});

  final String? message;
  final String? hint;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: Text(message ?? hint ?? "Location is unavailable."),
      leading: const Icon(Icons.location_off_outlined),
      actions: [
        TextButton(onPressed: onRetry, child: const Text("Retry")),
      ],
    );
  }
}