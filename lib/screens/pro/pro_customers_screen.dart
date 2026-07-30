import "package:flutter/material.dart";

class ProCustomersScreen extends StatelessWidget {
  const ProCustomersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text("Customers")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            "Customer network",
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            "Previous customers, repeat business, history, and future unlocks live here. It works like Party, tuned for verified service relationships.",
            style:
                theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          for (final row in const [
            ("Recent customers", "Follow up after completed Pro meetups."),
            (
              "Repeat opportunities",
              "Surface service reminders and seasonal needs."
            ),
            (
              "Broadcast unlock",
              "Send compliant customer messages when unlocked."
            ),
          ]) ...[
            ListTile(
              tileColor: cs.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              leading: const Icon(Icons.groups_2_outlined),
              title: Text(row.$1),
              subtitle: Text(row.$2),
              trailing: const Icon(Icons.chevron_right),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
