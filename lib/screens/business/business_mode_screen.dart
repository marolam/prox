import 'package:flutter/material.dart';

import 'package:prox/screens/business/business_dashboard_screen.dart';
import 'package:prox/screens/business/business_profile_screen.dart';
import 'package:prox/screens/monetization/business_paywall_screen.dart';
import 'package:prox/screens/settings/business_action_receipts_screen.dart';
import 'package:prox/screens/settings/business_avatar_settings_screen.dart';
import 'package:prox/screens/store/feature_example_screen.dart';
import 'package:prox/services/pro_mode_preview_access.dart';

/// Compatibility entry for the original Business Mode route. Access purchases
/// and profile editing use the same implementations as the rest of the app.
class BusinessModeScreen extends StatelessWidget {
  const BusinessModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!ProModePreviewAccess.instance.isAllowedForCurrentUser()) {
      return const FeatureExampleScreen();
    }
    void open(Widget page) => Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => page));

    return Scaffold(
      appBar: AppBar(title: const Text('Pro Mode')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'You have access to the limited Pro preview. Paid access is verified by the server. You can try the local tools examples at any time.',
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: const Text('Business HQ'),
            subtitle: const Text('Your profile, activity, and meetup metrics'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(const BusinessDashboardScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Business profile'),
            subtitle: const Text(
              'Edit your profile and available business details',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(const BusinessProfileScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: const Text('Pro access'),
            subtitle: const Text('Verified access and purchase options'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => BusinessPaywallScreen.open(context),
          ),
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('Try Pro tools'),
            subtitle: const Text(
              'Local request, promotion, and reply examples',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(const FeatureExampleScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('Try an away message'),
            subtitle: const Text('Preview and copy a reply'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(const BusinessAvatarSettingsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Action receipts'),
            subtitle: const Text('Recent actions recorded on this device'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(const BusinessActionReceiptsScreen()),
          ),
        ],
      ),
    );
  }
}
