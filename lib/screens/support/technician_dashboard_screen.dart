import 'package:flutter/material.dart';
import 'package:prox/screens/support/support_center_screen.dart';

class TechnicianDashboardScreen extends StatefulWidget {
  const TechnicianDashboardScreen({super.key});
  @override
  State<TechnicianDashboardScreen> createState() =>
      _TechnicianDashboardScreenState();
}

class _TechnicianDashboardScreenState extends State<TechnicianDashboardScreen> {
  final Map<String, String> _status = {
    'Location permission': 'Open',
    'No nearby matches': 'Open',
    'Report a safety concern': 'Open',
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Support practice queue')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Practice with fictional support tickets. Changes affect this example only. You are not claiming real tickets or contacting another person.',
        ),
        const SizedBox(height: 16),
        for (final entry in _status.entries)
          Card(
            child: ExpansionTile(
              title: Text('Example: ${entry.key}'),
              subtitle: Text(entry.value),
              childrenPadding: const EdgeInsets.all(16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(switch (entry.key) {
                  'Location permission' =>
                    'Ask whether location services are enabled and whether Prox has permission. Explain how to return to phone Settings after a permanent denial.',
                  'No nearby matches' =>
                    'Check profile keywords, radius, Party scope, connection, and whether another person is nearby. An empty result can be normal.',
                  _ =>
                    'Acknowledge the concern. For immediate danger, advise contacting local emergency services. Escalate the report through the support channel; do not investigate or promise an outcome.',
                }),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () =>
                          setState(() => _status[entry.key] = 'In progress'),
                      child: const Text('Practice taking ticket'),
                    ),
                    FilledButton(
                      onPressed: () => setState(
                        () => _status[entry.key] =
                            entry.key == 'Report a safety concern'
                            ? 'Escalated example'
                            : 'Resolved example',
                      ),
                      child: Text(
                        entry.key == 'Report a safety concern'
                            ? 'Practice escalation'
                            : 'Mark example resolved',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        TextButton(
          onPressed: () => setState(() {
            for (final key in _status.keys.toList()) {
              _status[key] = 'Open';
            }
          }),
          child: const Text('Reset practice queue'),
        ),
        const Divider(height: 32),
        OutlinedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const SupportCenterScreen(),
            ),
          ),
          child: const Text('Get help with a real issue'),
        ),
      ],
    ),
  );
}
