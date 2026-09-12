import 'package:flutter/material.dart';
import 'package:prox/screens/meetup/meetup_history_screen.dart';
import 'package:prox/screens/trust/trust_rules_screen.dart';

class TrustTimelineScreen extends StatelessWidget {
  const TrustTimelineScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Trust timeline')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Review your real meetup history and feedback. Historical score changes are only shown when a verified record exists; the example below explains a typical journey.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const MeetupHistoryScreen(),
            ),
          ),
          icon: const Icon(Icons.history),
          label: const Text('Open my meetup history'),
        ),
        const SizedBox(height: 20),
        Text('Example timeline', style: Theme.of(context).textTheme.titleLarge),
        const Text(
          'Illustrative events only. These are not events from your account and do not award points.',
        ),
        const Card(
          child: ExpansionTile(
            leading: Icon(Icons.handshake_outlined),
            title: Text('A meetup is accepted'),
            childrenPadding: EdgeInsets.all(16),
            children: [
              Text(
                'Both people agree to connect. Confirm timing and location in chat.',
              ),
            ],
          ),
        ),
        const Card(
          child: ExpansionTile(
            leading: Icon(Icons.place_outlined),
            title: Text('The meetup is completed'),
            childrenPadding: EdgeInsets.all(16),
            children: [
              Text(
                'Participants follow the meetup flow. Completion gives context for later feedback.',
              ),
            ],
          ),
        ),
        const Card(
          child: ExpansionTile(
            leading: Icon(Icons.thumb_up_outlined),
            title: Text('Feedback is submitted'),
            childrenPadding: EdgeInsets.all(16),
            children: [
              Text(
                'Each person can record their experience. Only verified records should affect a displayed trust summary.',
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const TrustRulesScreen()),
          ),
          child: const Text('How to build trust'),
        ),
      ],
    ),
  );
}
