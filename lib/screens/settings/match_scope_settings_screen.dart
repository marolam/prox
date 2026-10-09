import 'package:flutter/material.dart';
import 'package:prox/screens/discovery/matching_mode_screen.dart';
import 'package:prox/screens/settings/discovery_settings_screen.dart';

class MatchScopeSettingsScreen extends StatelessWidget {
  const MatchScopeSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Match settings')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Choose who you discover and how you match. Saved settings apply to nearby discovery.',
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.radar),
            title: const Text('Radius and Party scope'),
            subtitle: const Text(
              'Party Only, Party + Tree, or Public when your area unlocks.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DiscoverySettingsScreen(),
              ),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Matching mode'),
            subtitle: const Text(
              'Choose matching intent, keyword behavior, and availability.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MatchingModeScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'If your results are empty, try a wider radius or Party + Tree. Meet in person before joining each other\'s Party. Location permissions and another person\'s current availability also affect results.',
        ),
      ],
    ),
  );
}
