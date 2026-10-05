import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:prox/widgets/safety_access_shell.dart';

class MeetupFlowGuard extends StatefulWidget {
  const MeetupFlowGuard({
    super.key,
    required this.meetupId,
    required this.child,
  });
  final String meetupId;
  final Widget child;
  @override
  State<MeetupFlowGuard> createState() => _MeetupFlowGuardState();
}

class _MeetupFlowGuardState extends State<MeetupFlowGuard> {
  bool _asking = false;
  late final _stream = FirebaseFirestore.instance
      .doc('meetups/${widget.meetupId}')
      .snapshots();
  Future<void> _ask() async {
    if (_asking) return;
    _asking = true;
    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish this meetup step first'),
        content: const Text(
          'This meetup is active and step-locked to prevent confusion. Continue the current step, or open Safety to cancel by request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'continue'),
            child: const Text('Continue meetup'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'safety'),
            child: const Text('Safety / cancel'),
          ),
        ],
      ),
    );
    _asking = false;
    if (!mounted) return;
    if (decision == 'safety') SafetyAccessShell.open(context);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: _stream,
    builder: (context, snap) {
      final active = const {
        'requested',
        'accepted',
        'live',
      }.contains(snap.data?.data()?['status']);
      return PopScope(
        canPop: !active,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _ask();
        },
        child: widget.child,
      );
    },
  );
}
