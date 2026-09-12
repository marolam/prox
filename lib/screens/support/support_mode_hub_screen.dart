import 'package:flutter/material.dart';
import 'package:prox/screens/support/technician_dashboard_screen.dart';
import 'package:prox/screens/support/support_center_screen.dart';
import 'package:prox/screens/settings/user_guide_screen.dart';

class SupportModeHubScreen extends StatelessWidget {
  const SupportModeHubScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Community support')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Help someone get started',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Practice answering common questions with fictional tickets, or use the guide when helping someone navigate Prox. Practice does not enroll you as a technician, assign real tickets, or award points.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const TechnicianDashboardScreen(),
            ),
          ),
          icon: const Icon(Icons.school_outlined),
          label: const Text('Practice with sample tickets'),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const UserGuideScreen()),
          ),
          icon: const Icon(Icons.menu_book_outlined),
          label: const Text('Open the User’s Guide'),
        ),
        const Divider(height: 32),
        const Text(
          'Be respectful, describe only what you know, and never ask for a password or payment details. Escalate safety concerns through support. For an immediate emergency, contact local emergency services.',
        ),
        const SizedBox(height: 16),
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
