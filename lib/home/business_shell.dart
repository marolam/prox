import "package:flutter/material.dart";

import "package:prox/screens/business/business_dashboard_screen.dart";
import "package:prox/screens/business/business_leads_screen.dart";
import "package:prox/screens/business/business_profile_screen.dart";
import "package:prox/screens/matches/matches_screen.dart";
import "package:prox/screens/settings/settings_screen.dart";

class BusinessShell extends StatefulWidget {
  const BusinessShell({super.key});

  @override
  State<BusinessShell> createState() => _BusinessShellState();
}

class _BusinessShellState extends State<BusinessShell> {
  int _index = 0;

  static const List<_BizTab> _tabs = <_BizTab>[
    _BizTab(
      label: "HQ",
      icon: Icons.insights_outlined,
      child: BusinessDashboardScreen(),
    ),
    _BizTab(
      label: "Leads",
      icon: Icons.radar_outlined,
      child: BusinessLeadsScreen(),
    ),
    _BizTab(
      label: "Inbox",
      icon: Icons.forum_outlined,
      child: MatchesScreen(),
    ),
    _BizTab(
      label: "Profile",
      icon: Icons.badge_outlined,
      child: BusinessProfileScreen(),
    ),
    _BizTab(
      label: "Settings",
      icon: Icons.settings_outlined,
      child: SettingsScreen(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: KeyedSubtree(
          key: ValueKey<int>(_index),
          child: _tabs[_index].child,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        backgroundColor: cs.surface,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _tabs
            .map(
              (t) => NavigationDestination(
                icon: Icon(t.icon),
                label: t.label,
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _BizTab {
  final String label;
  final IconData icon;
  final Widget child;

  const _BizTab({
    required this.label,
    required this.icon,
    required this.child,
  });
}
