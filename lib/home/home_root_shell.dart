import "package:flutter/material.dart";
import "package:firebase_auth/firebase_auth.dart";

import "package:prox/home/home_shell.dart";
import "package:prox/models/user_settings.dart";
import "package:prox/screens/policy/code_of_conduct_screen.dart";
import "package:prox/services/points_service.dart";
import "package:prox/services/meetup_focus_lock_service.dart";
import "package:prox/services/meetup_service.dart";
import "package:prox/services/policy_ack_service.dart";
import "package:prox/services/pro_mode_preview_access.dart";
import "package:prox/services/user_settings_service.dart";

import "business_shell.dart";

class HomeRootShell extends StatefulWidget {
  const HomeRootShell({super.key});

  @override
  State<HomeRootShell> createState() => _HomeRootShellState();
}

class _HomeRootShellState extends State<HomeRootShell>
    with WidgetsBindingObserver {
  bool _checkingPrompt = false;
  DateTime? _lastPromptAt;
  String _restoredMeetupId = "";
  bool _restoringMeetup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MeetupFocusLockService.instance.addListener(_onMeetupFocusChanged);
    MeetupFocusLockService.instance.ensureStarted();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreMeetup());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MeetupFocusLockService.instance.removeListener(_onMeetupFocusChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _restoreMeetup();
  }

  void _onMeetupFocusChanged() => _restoreMeetup();

  Future<void> _restoreMeetup() async {
    if (!mounted || _restoringMeetup) return;
    final focus = MeetupFocusLockService.instance.state;
    if (!focus.active || focus.meetupId == _restoredMeetupId) return;
    _restoringMeetup = true;
    try {
      final screen =
          await MeetupService.instance.lastSessionScreen(focus.meetupId);
      if (!mounted || !MeetupFocusLockService.instance.isLocked) return;
      _restoredMeetupId = focus.meetupId;
      final route = switch (screen) {
        "chat" => "/chat",
        "live" => "/meetup_live",
        _ => "/meetup_plan",
      };
      await Navigator.of(context).pushNamed(
        route,
        arguments: <String, String>{
          "chatId": focus.meetupId,
          "otherUid": focus.otherUid,
        },
      );
    } finally {
      _restoringMeetup = false;
    }
  }

  Future<void> _maybePromptForAgreements(BuildContext context) async {
    if (_checkingPrompt) return;
    final now = DateTime.now();
    if (_lastPromptAt != null &&
        now.difference(_lastPromptAt!) < const Duration(minutes: 5)) {
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.trim().isEmpty) return;

    _checkingPrompt = true;
    _lastPromptAt = now;
    try {
      await PolicyAckService.instance.ensureLoaded();
      await PointsService.instance.refreshMeta(uid);
      final meta = PointsService.instance.peekMeta(uid);

      final bool needsConduct = meta.completedMeetups >= 5 &&
          !PolicyAckService.instance.isAcked(PolicyAckService.conductVersion);

      if (!mounted) return;

      if (needsConduct) {
        await showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) {
            final theme = Theme.of(ctx);
            return AlertDialog(
              title: const Text("Code of Conduct check-in"),
              content: Text(
                "You have completed 5+ meetups. Before continuing, please review and accept the Code of Conduct to keep Prox safe and privacy-first.",
                style: theme.textTheme.bodyMedium,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text("Later"),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const CodeOfConductScreen()),
                    );
                  },
                  child: const Text("Review now"),
                ),
              ],
            );
          },
        );
      }
    } finally {
      _checkingPrompt = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserSettings>(
      stream: UserSettingsService.instance.watch(),
      builder: (context, snap) {
        final settings = snap.data ?? UserSettingsService.instance.current;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // ignore: discarded_futures
          _maybePromptForAgreements(context);
        });

        final bool canUseProMode =
            ProModePreviewAccess.instance.isAllowedForCurrentUser();
        if (settings.uxMode == AppUxMode.business && canUseProMode) {
          return const BusinessShell();
        }
        if (settings.uxMode == AppUxMode.business && !canUseProMode) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            UserSettingsService.instance.setUxMode(AppUxMode.party);
          });
        }
        return const HomeShell();
      },
    );
  }
}
