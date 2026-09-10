import 'package:flutter/material.dart';
import 'package:prox/screens/incident/my_incidents_screen.dart';
import 'package:prox/screens/policy/policy_hub_screen.dart';

class TrustRulesScreen extends StatelessWidget {
  const TrustRulesScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Trust rulebook')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Trust grows through respectful, reliable interactions. A score is context about activity, not a guarantee of safety.',
        ),
        for (final rule in const [
          (
            title: 'Be clear about your intent',
            detail:
                'Describe accurately what you need and what you can offer. Keep your profile and availability current.',
          ),
          (
            title: 'Follow through or communicate',
            detail:
                'Agree on a clear plan. Tell the other person promptly if your timing changes or you need to cancel.',
          ),
          (
            title: 'Give honest feedback',
            detail:
                'Rate the meetup you actually experienced. Feedback is associated with a meetup; repeat taps should not create extra credit.',
          ),
          (
            title: 'Respect consent and boundaries',
            detail:
                'Accept that another person can decline a request or block contact. Do not pressure them to continue.',
          ),
          (
            title: 'Keep purchases separate from reputation',
            detail:
                'Cosmetics and local product examples do not establish someone’s trustworthiness.',
          ),
          (
            title: 'Ask for a review',
            detail:
                'Use My reports & appeals to reference an incident or decision and explain what should be reconsidered.',
          ),
        ])
          Card(
            child: ExpansionTile(
              title: Text(rule.title),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [Text(rule.detail)],
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const PolicyHubScreen()),
          ),
          child: const Text('Read community policies'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MyIncidentsScreen()),
          ),
          child: const Text('My reports & appeals'),
        ),
      ],
    ),
  );
}
