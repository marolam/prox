import "package:flutter/material.dart";

class StoreLockedSheet {
  const StoreLockedSheet._();

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String body,
    VoidCallback? onGoToAccount,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(body),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text("Close"),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: onGoToAccount == null
                        ? null
                        : () {
                            Navigator.of(ctx).pop();
                            onGoToAccount();
                          },
                    child: const Text("Account"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}