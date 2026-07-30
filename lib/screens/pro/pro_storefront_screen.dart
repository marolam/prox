import "package:flutter/material.dart";

class ProStorefrontScreen extends StatelessWidget {
  const ProStorefrontScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text("Storefront")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Public Pro profile",
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  "Hours, location, deals, match-card details, and immediate availability signals feed requesting users their best Pro choices.",
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            value: true,
            onChanged: (_) {},
            title: const Text("Immediate availability emphasized"),
            subtitle: const Text(
                "Pros closest to ready-now get the strongest automatic lead match signal."),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.schedule_outlined),
            title: Text("Hours and service windows"),
            subtitle: Text("Set when customers can request a Pro match."),
          ),
          const ListTile(
            leading: Icon(Icons.local_offer_outlined),
            title: Text("Deals and match-card offers"),
            subtitle:
                Text("Show useful offers without encouraging stale leads."),
          ),
          const ListTile(
            leading: Icon(Icons.place_outlined),
            title: Text("Service area and meetup terms"),
            subtitle:
                Text("Define where transactions can happen after agreement."),
          ),
        ],
      ),
    );
  }
}
