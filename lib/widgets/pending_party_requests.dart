import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:prox/services/party_connection_service.dart';
import 'package:prox/services/user_profile_service.dart';
import 'package:prox/widgets/meetup_rating_form.dart';
import 'package:prox/services/simple_mode/simple_mode_policy.dart';
import 'package:prox/services/user_settings_service.dart';

class PendingPartyRequests extends StatefulWidget {
  const PendingPartyRequests({super.key});
  @override
  State<PendingPartyRequests> createState() => _PendingPartyRequestsState();
}

class _PendingPartyRequestsState extends State<PendingPartyRequests> {
  Timer? _clock;
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<List<PendingPartyConnection>>(
      stream: PartyConnectionService.instance.watchPending(uid),
      builder: (context, snapshot) {
        final pending = (snapshot.data ?? [])
            .where((p) => p.isActive(DateTime.now()))
            .toList();
        return Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pending Party Add',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'You join each other’s Party only when you both agree. Requests expire after 7 days without activity.',
                ),
                if (snapshot.hasError)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Could not load pending requests. Check your connection and reopen Party.',
                    ),
                  )
                else if (snapshot.connectionState == ConnectionState.waiting)
                  const LinearProgressIndicator()
                else if (pending.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('No pending requests.'),
                  )
                else
                  ...pending.map(
                    (p) => StreamBuilder<UserProfile?>(
                      key: ValueKey(p.otherUid),
                      stream: UserProfileService.instance.watchProfile(
                        p.otherUid,
                      ),
                      builder: (context, profile) => PendingPartyRequestCard(
                        partyRequiresNormalMode: SimpleModePolicy.isActive,
                        connection: p,
                        name: profile.data?.displayName ?? 'Meetup partner',
                        onAction: (action) async {
                          final result = await PartyConnectionService.instance
                              .act(p.otherUid, action);
                          if (action == 'add' && SimpleModePolicy.isActive) {
                            UserSettingsService.instance
                                .unlockPartyFromSimpleMode();
                          }
                          return result;
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class PendingPartyRequestCard extends StatefulWidget {
  const PendingPartyRequestCard({
    super.key,
    required this.connection,
    required this.name,
    required this.onAction,
    this.partyRequiresNormalMode = false,
  });
  final PendingPartyConnection connection;
  final String name;
  final Future<String> Function(String action) onAction;
  final bool partyRequiresNormalMode;
  @override
  State<PendingPartyRequestCard> createState() =>
      _PendingPartyRequestCardState();
}

class _PendingPartyRequestCardState extends State<PendingPartyRequestCard> {
  bool _busy = false;
  String? _message;
  Future<void> _act(String action) async {
    final title = switch (action) {
      'add' => 'Add to Party?',
      'later' => 'Not Right Now?',
      'remind' => 'Send a reminder?',
      _ => 'Block this user?',
    };
    final label = switch (action) {
      'add' => 'Add to Party',
      'later' => 'Not Right Now',
      'remind' => 'Remind',
      _ => 'Block',
    };
    final message = switch (action) {
      'add' =>
        'If they also agree, you will both join each other’s Party and share the profile information marked Party Visible.',
      'later' =>
        'You will not join each other’s Party. This request stays pending for 7 days without activity.',
      'remind' =>
        'Send another Party request to this person? You can send one reminder every 24 hours.',
      _ =>
        'This cancels your Party connection and prevents further requests and contact from this person. You can unblock them in Settings.',
    };
    if (!await confirmPartyDecision(
          context,
          title: title,
          message:
              (action == 'add' && widget.partyRequiresNormalMode
                  ? 'This also switches you to Normal Mode so you can open Party. '
                  : '') +
              message,
          confirmLabel: label,
        ) ||
        !mounted)
      return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final status = await widget
          .onAction(action)
          .timeout(const Duration(seconds: 35));
      if (mounted)
        setState(
          () => _message = status == 'connected'
              ? 'You are now in each other’s Party.'
              : action == 'remind'
              ? 'Reminder sent.'
              : action == 'block'
              ? 'User blocked.'
              : 'Response saved.',
        );
    } catch (error) {
      if (mounted)
        setState(
          () => _message = error is FirebaseFunctionsException
              ? error.message ?? 'Could not save. Try again.'
              : 'Could not save. Check your connection and try again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.connection;
    final now = DateTime.now();
    if (!p.isActive(now)) return const SizedBox.shrink();
    final days = (p.expiresAt.difference(now).inMinutes / 1440).ceil();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.name, style: Theme.of(context).textTheme.titleMedium),
          Text(
            p.myDecision == 'add'
                ? 'Pending Party Acceptance — waiting for their response.'
                : p.theirDecision == 'add'
                ? 'They would like to add you to Party.'
                : 'You can choose to connect later.',
          ),
          Text(
            'Expires in $days ${days == 1 ? 'day' : 'days'} without activity.',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (p.myDecision != 'add')
                FilledButton(
                  onPressed: _busy ? null : () => _act('add'),
                  child: const Text('Add to Party'),
                ),
              if (p.myDecision == 'add')
                OutlinedButton(
                  onPressed: _busy || !p.canRemind(now)
                      ? null
                      : () => _act('remind'),
                  child: const Text('Remind'),
                ),
              if (p.myDecision != 'later')
                TextButton(
                  onPressed: _busy ? null : () => _act('later'),
                  child: const Text('Not Right Now'),
                ),
              TextButton(
                onPressed: _busy ? null : () => _act('block'),
                child: const Text('Block'),
              ),
            ],
          ),
          if (p.myDecision == 'add' && !p.canRemind(now))
            const Text('Reminders are available once every 24 hours.'),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null) Text(_message!),
          const Divider(),
        ],
      ),
    );
  }
}
