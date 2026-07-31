import "dart:async";

import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:prox/services/chat/chat_gate_service.dart";
import "package:prox/services/matching/active_mode_policy_service.dart";

class GlobalChatAcceptCountdownBanner extends StatefulWidget {
  const GlobalChatAcceptCountdownBanner({
    super.key,
    required this.navigatorKey,
  });

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<GlobalChatAcceptCountdownBanner> createState() =>
      _GlobalChatAcceptCountdownBannerState();
}

class _GlobalChatAcceptCountdownBannerState
    extends State<GlobalChatAcceptCountdownBanner> {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DateTime?>? _deadlineSub;
  Timer? _clockTick;
  DateTime? _deadline;
  String _uid = "";

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _bindForUser(user?.uid ?? "");
    });
    _bindForUser(FirebaseAuth.instance.currentUser?.uid ?? "");

    _clockTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_uid.isNotEmpty) {
        ActiveModePolicyService.instance.evaluateAndApplyPenaltyIfNeeded();
        unawaited(
          ChatGateService.instance.enforceExpiredIncomingRequestsIfNeeded(
            forUid: _uid,
          ),
        );
      }
      setState(() {});
    });
  }

  void _bindForUser(String uid) {
    final nextUid = uid.trim();
    if (_uid == nextUid && _deadlineSub != null) return;

    _uid = nextUid;
    _deadlineSub?.cancel();
    _deadlineSub = null;

    if (_uid.isEmpty) {
      if (mounted) {
        setState(() {
          _deadline = null;
        });
      } else {
        _deadline = null;
      }
      return;
    }

    _deadlineSub = ChatGateService.instance
        .watchIncomingRequestDeadline(forUid: _uid)
        .listen((deadline) {
      if (!mounted) return;
      setState(() {
        _deadline = deadline;
      });
    });
  }

  @override
  void dispose() {
    _clockTick?.cancel();
    _authSub?.cancel();
    _deadlineSub?.cancel();
    super.dispose();
  }

  String _fmtMMSS(Duration d) {
    final s = d.inSeconds < 0 ? 0 : d.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, "0");
    final ss = (s % 60).toString().padLeft(2, "0");
    return "$mm:$ss";
  }

  @override
  Widget build(BuildContext context) {
    if (ChatGateService.instance.shouldSuppressIncomingCountdownForUid(_uid)) {
      return const SizedBox.shrink();
    }

    final due = _deadline;
    if (due == null) return const SizedBox.shrink();

    final left = due.difference(DateTime.now());
    if (left <= Duration.zero) {
      return const SizedBox.shrink();
    }

    final top = MediaQuery.of(context).padding.top + 8;
    final cs = Theme.of(context).colorScheme;

    return Positioned(
      top: top,
      left: 12,
      right: 12,
      child: SafeArea(
        bottom: false,
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFDE5353).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.timer, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Accept chat in ${_fmtMMSS(left)} or Active switches to Passive for 10:00.",
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    final nav = widget.navigatorKey.currentState;
                    if (nav == null) return;
                    nav.pushNamed("/nearby");
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: cs.onError,
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    minimumSize: const Size(44, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: const Text("Open"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
