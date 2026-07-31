/*
 * lib/home/home_shell.dart
 *
 * Production-safe HomeShell (Material 3).
 * Swipe tabs (2 pages x 5):
 * - Page 1: Nearby / Matches / Meetups / Party / Profile
 * - Page 2: HQ / Referrals / Support / Settings
 *
 * Triage add-on (tester build):
 * - Help Mode: long-press anywhere OR tap the ? button (top-left).
 */

import "dart:async";

import "package:flutter/material.dart";

import "package:prox/screens/match_inbox/match_inbox_screen.dart";
import "package:prox/screens/matches/matches_screen.dart";
import "package:prox/screens/meetup/meetup_history_screen.dart";
import "package:prox/screens/party/party_screen.dart";
import "package:prox/screens/profile/profile_screen.dart";
import "package:prox/screens/dashboard/dashboard_screen.dart";
import "package:prox/screens/referral/referrals_hub_screen.dart";
import "package:prox/screens/support/support_hub_screen.dart";
import "package:prox/screens/settings/settings_screen.dart";
import "package:prox/screens/settings/support_feedback_screen.dart";
import "package:prox/services/help/context_help_service.dart";

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _showSwipeHint = true;
  late final PageController _navPageController;
  int _testerComboLongPressCount = 0;
  bool _suppressNextFeedbackTap = false;
  DateTime? _testerComboArmedUntil;
  Timer? _testerComboResetTimer;
  static const int _testerComboLongPressGoal = 3;

  static const int _tabsPerPage = 5;

  static const List<_ShellTab> _tabs = <_ShellTab>[
    _ShellTab(
      label: "Nearby",
      icon: Icons.radar,
      child: MatchInboxScreen(),
    ),
    _ShellTab(
      label: "Matches",
      icon: Icons.chat_bubble_outline,
      child: MatchesScreen(),
    ),
    _ShellTab(
      label: "Meetups",
      icon: Icons.event_available_outlined,
      child: MeetupHistoryScreen(),
    ),
    _ShellTab(
      label: "Party",
      icon: Icons.groups_outlined,
      child: PartyScreen(),
    ),
    _ShellTab(
      label: "Profile",
      icon: Icons.person_outline,
      child: ProfileScreen(),
    ),
    _ShellTab(
      label: "HQ",
      icon: Icons.dashboard_outlined,
      child: DashboardScreen(),
    ),
    _ShellTab(
      label: "Referrals",
      icon: Icons.share_outlined,
      child: ReferralsHubScreen(),
    ),
    _ShellTab(
      label: "Support",
      icon: Icons.support_agent_outlined,
      child: SupportHubScreen(),
    ),
    _ShellTab(
      label: "Settings",
      icon: Icons.settings_outlined,
      child: SettingsScreen(),
    ),
  ];

  static int _pageForIndex(int i) => i ~/ _tabsPerPage;

  int get _pageCount => (_tabs.length / _tabsPerPage).ceil();

  @override
  void initState() {
    super.initState();
    _navPageController = PageController(initialPage: _pageForIndex(_index));
    _syncHelpContext();
  }

  @override
  void dispose() {
    _testerComboResetTimer?.cancel();
    ContextHelpService.instance.setContext(null);
    _navPageController.dispose();
    super.dispose();
  }

  void _openFeedback() {
    final NavigatorState nav = Navigator.of(context);
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const SupportFeedbackScreen(),
      ),
    );
  }

  void _openDevMenu() {
    final NavigatorState nav = Navigator.of(context);
    nav.pushNamed("/dev/menu");
  }

  void _resetTesterCombo() {
    _testerComboResetTimer?.cancel();
    _testerComboLongPressCount = 0;
    _testerComboArmedUntil = null;
  }

  void _armTesterMenuCombo() {
    final now = DateTime.now();

    if (_testerComboArmedUntil == null || now.isAfter(_testerComboArmedUntil!)) {
      _resetTesterCombo();
    }

    _testerComboResetTimer?.cancel();
    _testerComboLongPressCount += 1;
    _testerComboArmedUntil = now.add(const Duration(seconds: 12));
    _testerComboResetTimer = Timer(const Duration(seconds: 12), _resetTesterCombo);

    if (_testerComboLongPressCount >= _testerComboLongPressGoal) {
      _resetTesterCombo();
      _openDevMenu();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Dev combo: ${_testerComboLongPressCount}/${_testerComboLongPressGoal} long-presses")),
    );
  }

  void _onFeedbackPressed() {
    if (_suppressNextFeedbackTap) {
      _suppressNextFeedbackTap = false;
      return;
    }
    _openFeedback();
  }

  void _onFeedbackLongPress() {
    _suppressNextFeedbackTap = true;
    _armTesterMenuCombo();
  }

  void _syncHelpContext() {
    final label = _tabs[_index].label;
    ContextHelpService.instance.setContext("home:${label.toLowerCase()}");
  }

  void _selectTab(int index) {
    setState(() {
      _index = index;
      _syncHelpContext();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int currentPage = _pageForIndex(_index);

    final scaffold = Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: KeyedSubtree(
          key: ValueKey<int>(_index),
          child: _tabs[_index].child,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            GestureDetector(
              onLongPress: _onFeedbackLongPress,
              child: FloatingActionButton.extended(
                heroTag: "fab_feedback",
                onPressed: _onFeedbackPressed,
                icon: const Icon(Icons.flag_outlined),
                label: const Text("Feedback"),
                tooltip: "Send feedback / bug report",
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: cs.surface,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 76,
                child: PageView.builder(
                  controller: _navPageController,
                  itemCount: _pageCount,
                  onPageChanged: (page) {
                    setState(() {
                      if (_showSwipeHint && page > 0) {
                        _showSwipeHint = false;
                      }
                    });
                  },
                  itemBuilder: (context, page) {
                    final int start = page * _tabsPerPage;
                    final int end = (start + _tabsPerPage).clamp(0, _tabs.length);
                    final tabs = _tabs.sublist(start, end);

                    return Row(
                      children: [
                        for (int i = 0; i < tabs.length; i++)
                          Expanded(
                            child: _NavButton(
                              tab: tabs[i],
                              selected: _index == (start + i),
                              onTap: () => _selectTab(start + i),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: _showSwipeHint ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !_showSwipeHint,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.swipe, size: 13, color: cs.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(
                          "Swipe for more",
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(_pageCount, (i) {
                  final bool active = i == currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 16 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? cs.primary : cs.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );

    return scaffold;
  }
}

class _ShellTab {
  final String label;
  final IconData icon;
  final Widget child;

  const _ShellTab({
    required this.label,
    required this.icon,
    required this.child,
  });
}

class _NavButton extends StatelessWidget {
  final _ShellTab tab;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final width = MediaQuery.of(context).size.width;
    final bool compact = width < 380;
    final double iconSize = compact ? 20 : 22;
    final double labelSize = compact ? 10 : 11;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 7 : 6, horizontal: compact ? 1 : 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              tab.icon,
              size: iconSize,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
            SizedBox(height: compact ? 3 : 4),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: labelSize,
                color: selected ? cs.primary : cs.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: compact ? -0.1 : 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
