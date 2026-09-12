import 'package:flutter/material.dart';
import 'package:prox/screens/support/support_center_screen.dart';
import 'package:prox/screens/support/user_support_screen.dart';
import 'package:prox/screens/support/support_mode_hub_screen.dart';
import 'package:prox/screens/incident/my_incidents_screen.dart';
import 'package:prox/screens/dev/bug_reports/bug_reports_list_screen.dart';
import 'package:prox/services/help/context_help_service.dart';

class SupportHubScreen extends StatelessWidget {
  const SupportHubScreen({super.key});

  Future<void> _open(BuildContext context, Widget page, String key) async {
    final previous = ContextHelpService.instance.contextKey.value;
    ContextHelpService.instance.setContext(key);
    try {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => page));
    } finally {
      ContextHelpService.instance.setContext(previous);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Support & feedback')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'How can we help?',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Ask for help, report a problem, or follow the status of a submission.',
        ),
        const SizedBox(height: 16),
        for (final item
            in const <
              ({
                String title,
                String detail,
                String key,
                IconData icon,
                Widget page,
              })
            >[
              (
                title: 'Support center',
                detail: 'Write a message or return to a saved draft.',
                key: 'support:support_center',
                icon: Icons.support_agent_outlined,
                page: SupportCenterScreen(),
              ),
              (
                title: 'My support tickets',
                detail: 'Read your submitted messages and status updates.',
                key: 'support:ticket_dashboard',
                icon: Icons.confirmation_number_outlined,
                page: UserSupportScreen(),
              ),
              (
                title: 'My bug reports',
                detail: 'Describe a reproducible issue and follow its status.',
                key: 'support:bug_reports',
                icon: Icons.bug_report_outlined,
                page: BugReportsListScreen(),
              ),
              (
                title: 'My reports & appeals',
                detail: 'Report an incident or request review of a decision.',
                key: 'support:incidents',
                icon: Icons.shield_outlined,
                page: MyIncidentsScreen(),
              ),
              (
                title: 'Community support practice',
                detail: 'Learn with sample tickets and the User’s Guide.',
                key: 'support:practice',
                icon: Icons.school_outlined,
                page: SupportModeHubScreen(),
              ),
            ])
          Card(
            child: ListTile(
              leading: Icon(item.icon),
              title: Text(item.title),
              subtitle: Text(item.detail),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, item.page, item.key),
            ),
          ),
      ],
    ),
  );
}
