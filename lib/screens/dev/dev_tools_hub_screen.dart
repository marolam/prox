import 'package:flutter/material.dart';
import 'package:prox/screens/dev/system_health_hud_screen.dart';
import 'package:prox/screens/dev/bug_reports/bug_reports_list_screen.dart';
import 'package:prox/screens/dev/missing_sweep_check_screen.dart';
import 'package:prox/screens/review/release_candidate_checklist_screen.dart';
import 'package:prox/screens/review/tester_mission_screen.dart';
import 'package:prox/dev/dev_user_simulator_screen.dart';
import 'package:prox/screens/store/feature_example_screen.dart';

class DevToolsHubScreen extends StatelessWidget {
  const DevToolsHubScreen({super.key, this.title = 'Tester tools'});
  final String title;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Check the running app, complete a repeatable mission, and practice with isolated examples.',
        ),
        const SizedBox(height: 16),
        for (final tool
            in const <
              ({String title, String detail, IconData icon, Widget page})
            >[
              (
                title: 'System health',
                detail: 'Device checks, app version, and recent local issues.',
                icon: Icons.monitor_heart_outlined,
                page: SystemHealthHudScreen(),
              ),
              (
                title: 'My bug reports',
                detail: 'Submit a reproducible problem and track its status.',
                icon: Icons.bug_report_outlined,
                page: BugReportsListScreen(),
              ),
              (
                title: 'Tester mission',
                detail: 'A resumable walkthrough of the complete journey.',
                icon: Icons.checklist,
                page: TesterMissionScreen(),
              ),
              (
                title: 'Release checklist',
                detail: 'Manual Android and iOS verification steps.',
                icon: Icons.verified_outlined,
                page: ReleaseCandidateChecklistScreen(),
              ),
              (
                title: 'Feature sweep',
                detail: 'Find missing actions and incomplete states.',
                icon: Icons.fact_check_outlined,
                page: MissingSweepCheckScreen(),
              ),
              (
                title: 'Discovery simulator',
                detail: 'Adjust filters against fictional local profiles.',
                icon: Icons.radar,
                page: DevUserSimulatorScreen(),
              ),
              (
                title: 'Pro tools example',
                detail: 'Try sample requests, promotions, and reply templates.',
                icon: Icons.work_outline,
                page: FeatureExampleScreen(),
              ),
            ])
          Card(
            child: ListTile(
              leading: Icon(tool.icon),
              title: Text(tool.title),
              subtitle: Text(tool.detail),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => tool.page)),
            ),
          ),
      ],
    ),
  );
}
