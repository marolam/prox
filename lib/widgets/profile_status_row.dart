import "package:flutter/material.dart";

class ProfileStatusRow extends StatelessWidget {
  const ProfileStatusRow({
    super.key,
    required this.uid,
  });

  final String uid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(
          avatar: const Icon(Icons.verified_user_outlined, size: 16),
          label: const Text("Identity"),
          backgroundColor: cs.surface,
        ),
        Chip(
          avatar: const Icon(Icons.bolt_outlined, size: 16),
          label: Text(uid.isEmpty ? "Guest" : "Member"),
          backgroundColor: cs.surface,
        ),
      ],
    );
  }
}
