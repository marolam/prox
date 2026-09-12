import 'package:flutter/material.dart';
import 'package:prox/screens/referral/referral_demo_walkthrough_screen.dart';
import 'package:prox/screens/settings/discovery_settings_screen.dart';
import 'package:prox/screens/settings/sound_alert_settings_screen.dart';
import 'package:prox/screens/settings/privacy/blocked_users_screen.dart';
import 'package:prox/screens/policy/policy_hub_screen.dart';
import 'package:prox/screens/support/support_center_screen.dart';
import 'package:prox/screens/dev/bug_reports/bug_reports_list_screen.dart';
import 'package:prox/screens/review/tester_mission_screen.dart';

class UserGuideScreen extends StatefulWidget {
  const UserGuideScreen({super.key});
  @override
  State<UserGuideScreen> createState() => _UserGuideScreenState();
}

class _UserGuideScreenState extends State<UserGuideScreen> {
  String _query = '';
  static const _topics = <({String title, String detail, IconData icon, String action, Widget page})>[
    (
      title: 'Start here: the Prox journey',
      detail:
          'Build your profile, discover a useful nearby connection, request a meetup, coordinate in chat, then share feedback. The walkthrough uses examples and can be replayed at any time.',
      icon: Icons.explore_outlined,
      action: 'Play the walkthrough',
      page: ReferralDemoWalkthroughScreen(),
    ),
    (
      title: 'Get better nearby matches',
      detail:
          'Looking For describes what you need; Can Provide describes what you offer. Use specific keywords. Choose a radius and Party scope that suit you. If no one appears, check location permission, your filters, and whether another person is currently nearby.',
      icon: Icons.radar,
      action: 'Open discovery settings',
      page: DiscoverySettingsScreen(),
    ),
    (
      title: 'Requests, chat, and meetups',
      detail:
          'A meetup begins with a request that the other person accepts. Use chat to agree on a time and public meeting point. Follow the live meetup status and rate your experience after completion.',
      icon: Icons.handshake_outlined,
      action: 'Try the tester mission',
      page: TesterMissionScreen(),
    ),
    (
      title: 'Safety, blocking, and reports',
      detail:
          'Share only what you are comfortable sharing. Block unwanted contact and use My reports & appeals for an incident or appeal. Contact local emergency services if you are in immediate danger.',
      icon: Icons.shield_outlined,
      action: 'Manage blocked users',
      page: BlockedUsersScreen(),
    ),
    (
      title: 'Sounds and notifications',
      detail:
          'Choose match notifications and cues in Sound & alerts. Your phone notification permissions, volume, silent mode, and background restrictions can also affect delivery.',
      icon: Icons.notifications_outlined,
      action: 'Adjust sound and alerts',
      page: SoundAlertSettingsScreen(),
    ),
    (
      title: 'Trust and community rules',
      detail:
          'Be accurate about what you offer, respect consent, communicate changes, and follow through on meetups. Report concerns through support; a cosmetic item or preview is not a trust endorsement.',
      icon: Icons.menu_book_outlined,
      action: 'Read community policies',
      page: PolicyHubScreen(),
    ),
    (
      title: 'Troubleshoot a problem',
      detail:
          'Check your connection and app version first. Reopen the affected screen and use Retry if shown. A useful bug report includes your phone model, app version, exact steps, and what you expected.',
      icon: Icons.bug_report_outlined,
      action: 'Open my bug reports',
      page: BugReportsListScreen(),
    ),
    (
      title: 'Get support or share an idea',
      detail:
          'Write a support message in the app. Saved drafts remain on this device; submitted tickets appear in your ticket dashboard. Opening your email app does not confirm a message was sent.',
      icon: Icons.support_agent_outlined,
      action: 'Open support center',
      page: SupportCenterScreen(),
    ),
  ];
  @override
  Widget build(BuildContext context) {
    final matches = _topics
        .where(
          (t) => '${t.title} ${t.detail}'.toLowerCase().contains(
            _query.toLowerCase(),
          ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('User’s Guide')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Make your next connection',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Search the guide or open a topic for a practical next step.',
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search the guide',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
          const SizedBox(height: 16),
          if (matches.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No topics found. Try “matches”, “privacy”, or “support”.',
              ),
            ),
          for (final topic in matches)
            Card(
              child: ExpansionTile(
                key: ValueKey(topic.title),
                leading: Icon(topic.icon),
                title: Text(topic.title),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(topic.detail),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: (_) => topic.page)),
                    child: Text(topic.action),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
