import "package:flutter/material.dart";

class InAppNotificationBanner extends StatelessWidget {
  const InAppNotificationBanner({
    super.key,
    required this.title,
    required this.body,
    required this.type,
    this.onTap,
    this.onDismiss,
  });

  final String title;
  final String body;
  final String type;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        leading: const Icon(Icons.notifications_active_outlined),
        title: Text(title),
        subtitle: Text(body),
        onTap: onTap,
        trailing: IconButton(
          tooltip: "Dismiss",
          icon: const Icon(Icons.close),
          onPressed: onDismiss,
        ),
      ),
    );
  }
}