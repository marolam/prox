import "package:flutter/material.dart";

class ProInsightsScreen extends StatelessWidget {
  const ProInsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const keywords = <String>[
      "same day",
      "licensed",
      "pickup",
      "repair",
      "quote",
      "installation"
    ];
    return Scaffold(
      appBar: AppBar(title: const Text("Insights")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _MetricTile(label: "Lead response", value: "92%"),
              _MetricTile(label: "Deals won", value: "18"),
              _MetricTile(label: "Avg. close", value: "24m"),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            "Top lead keywords",
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: keywords
                .map((keyword) => ActionChip(
                      label: Text(keyword),
                      avatar: const Icon(Icons.add, size: 18),
                      onPressed: () {},
                    ))
                .toList(growable: false),
          ),
          const SizedBox(height: 18),
          Text(
            "Pro unlocks",
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          for (final item in const [
            (
              "Priority matching",
              "Rise faster when your trust and availability are excellent."
            ),
            (
              "Customer broadcast",
              "Reach previous customers with compliant future offers."
            ),
            (
              "Custom match cards",
              "Make your requesting-user card clearer and more appealing."
            ),
            (
              "Data growth pack",
              "Use app demand data to tune services and pricing."
            ),
          ]) ...[
            ListTile(
              tileColor: cs.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(item.$1),
              subtitle: Text(item.$2),
              trailing: const Icon(Icons.lock_outline),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: 104,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
