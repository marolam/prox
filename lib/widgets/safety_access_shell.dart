import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:prox/services/safety_session_service.dart';

/// Reserved space outside the navigator: accessible over dialogs and keyboards.
class SafetyAccessShell extends StatefulWidget {
  static void open(BuildContext context) =>
      context.findAncestorStateOfType<_SafetyAccessShellState>()?._show();
  const SafetyAccessShell({
    super.key,
    required this.child,
    this.loadSessions,
    this.endSession,
    this.openPhone,
  });
  final Widget child;
  final Stream<List<SafetySession>> Function()? loadSessions;
  final Future<void> Function(String id, bool endChat)? endSession;
  final Future<bool> Function()? openPhone;
  @override
  State<SafetyAccessShell> createState() => _SafetyAccessShellState();
}

class _SafetyAccessShellState extends State<SafetyAccessShell> {
  bool _open = false;
  Stream<List<SafetySession>>? _sessions;
  void _show() {
    if (!_open) _toggle();
  }

  void _toggle() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _open = !_open;
      if (_open) {
        final loader = widget.loadSessions;
        if (loader != null) {
          _sessions = loader();
        } else {
          // Emergency dialing never depends on Firebase startup or sign-in.
          try {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            _sessions = uid == null
                ? Stream.value([])
                : SafetySessionService.watch(uid);
          } catch (_) {
            _sessions = Stream.value([]);
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => Material(
    child: SafeArea(
      bottom: false,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _toggle,
              icon: const Icon(Icons.health_and_safety_outlined),
              label: Text(_open ? 'Close Safety' : 'Safety'),
              style: TextButton.styleFrom(minimumSize: const Size(100, 48)),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: widget.child,
                  ),
                ),
                if (_open)
                  Positioned.fill(
                    child: Material(
                      child: SafetyPanel(
                        sessions: _sessions!,
                        endSession:
                            widget.endSession ??
                            (id, endChat) =>
                                SafetySessionService.end(id, endChat: endChat),
                        openPhone:
                            widget.openPhone ??
                            () => launchUrl(Uri(scheme: 'tel', path: '911')),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class SafetyPanel extends StatefulWidget {
  const SafetyPanel({
    super.key,
    required this.sessions,
    required this.endSession,
    required this.openPhone,
  });
  final Stream<List<SafetySession>> sessions;
  final Future<void> Function(String id, bool endChat) endSession;
  final Future<bool> Function() openPhone;
  @override
  State<SafetyPanel> createState() => _SafetyPanelState();
}

class _SafetyPanelState extends State<SafetyPanel> {
  String? _busy;
  String? _message;
  final Set<String> _ended = {};
  final Set<String> _cancelledMeetups = {};
  List<SafetySession>? _sessionData;
  bool _sessionError = false;
  StreamSubscription<List<SafetySession>>? _subscription;
  @override
  void initState() {
    super.initState();
    _subscription = widget.sessions.listen(
      (data) {
        if (mounted) setState(() => _sessionData = data);
      },
      onError: (Object _) {
        if (mounted) setState(() => _sessionError = true);
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _end(SafetySession session, bool endChat) async {
    if (_busy != null) return;
    setState(() {
      _busy = session.id;
      _message = null;
    });
    try {
      await widget.endSession(session.id, endChat);
      if (!mounted) return;
      setState(() {
        if (endChat || !session.hasChat) {
          _ended.add(session.id);
        } else {
          _cancelledMeetups.add(session.id);
        }
        _message = endChat && session.isGroup
            ? 'You left the group. Other members can continue chatting.'
            : endChat
            ? 'Chat ended. Any active meetup was cancelled.'
            : 'Meetup cancelled. Chat remains available.';
      });
    } catch (_) {
      if (mounted)
        setState(
          () => _message =
              'Cancellation has not been confirmed. Check your connection and retry. You can leave now; you do not need to wait for the app.',
        );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _call() async {
    try {
      if (await widget.openPhone()) return;
    } catch (_) {
      /* Show manual fallback. */
    }
    if (mounted)
      setState(
        () => _message =
            'Could not open the phone app. Use your phone’s Emergency Call feature or dial 911 in the US. Outside the US, dial your local emergency number.',
      );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        'Safety & leaving a session',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text(
        'You can leave at any time. You do not need the other person’s permission.',
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _call,
        icon: const Icon(Icons.phone),
        label: const Text('Open phone to call 911 (US)'),
      ),
      const Text(
        'Your phone may ask you to confirm the call. Outside the US, use your local emergency number. Prox does not dispatch help or automatically share your location with emergency services.',
      ),
      const Divider(height: 32),
      if (_message != null)
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_message!),
          ),
        ),
      const Text(
        'Confirm an exit below. Cancelling ends the meetup for both people without a rating penalty. Ending a direct chat stops new messages. Leaving a group removes you; if you manage it, another member takes over. These actions do not contact emergency services.',
      ),
      Builder(
        builder: (context) {
          final sessions = (_sessionData ?? [])
              .where((s) => !_ended.contains(s.id))
              .map(
                (s) => _cancelledMeetups.contains(s.id)
                    ? SafetySession(
                        id: s.id,
                        otherUid: s.otherUid,
                        hasMeetup: false,
                        hasChat: s.hasChat,
                        isGroup: s.isGroup,
                      )
                    : s,
              )
              .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_sessionError)
                const Text(
                  'Some sessions could not be loaded. Check your connection and reopen Safety. Emergency dialing is still available.',
                ),
              if (_sessionData == null && !_sessionError)
                const LinearProgressIndicator(),
              if (_sessionData != null && sessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No active chat or meetup to cancel.'),
                ),
              for (final session in sessions)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SessionName(session: session),
                        if (session.hasMeetup)
                          OutlinedButton(
                            onPressed: _busy != null
                                ? null
                                : () => _end(session, false),
                            child: const Text('Confirm: cancel meetup'),
                          ),
                        if (session.hasChat)
                          FilledButton(
                            onPressed: _busy != null
                                ? null
                                : () => _end(session, true),
                            child: Text(
                              session.isGroup
                                  ? 'Confirm: leave group'
                                  : session.hasMeetup
                                  ? 'Confirm: end chat & meetup'
                                  : 'Confirm: end chat',
                            ),
                          ),
                        if (_busy == session.id)
                          const LinearProgressIndicator(),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class _SessionName extends StatelessWidget {
  const _SessionName({required this.session});
  final SafetySession session;
  @override
  Widget build(BuildContext context) {
    // A label remains available even during a profile lookup failure.
    Stream<DocumentSnapshot<Map<String, dynamic>>>? stream;
    try {
      stream = FirebaseFirestore.instance
          .doc('publicProfiles/${session.otherUid}')
          .snapshots();
    } catch (_) {}
    return StreamBuilder(
      stream: stream,
      builder: (context, snap) {
        final data = snap.data?.data();
        final name = data?['alias'] ?? data?['displayName'] ?? session.otherUid;
        return Text(
          session.isGroup
              ? 'Group chat including $name'
              : '${session.hasMeetup ? 'Meetup' : 'Chat'} with $name',
          style: Theme.of(context).textTheme.titleMedium,
        );
      },
    );
  }
}
