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
  bool _allowLeave = false;
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
        title: const Text('Leave this meetup pending?'),
        content: const Text(
          'Going back does not cancel the meetup. You can resume before its deadline. If it remains unfinished, it closes without completion credit. Use Safety to cancel now without a rating penalty.',
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
          TextButton(
            onPressed: () => Navigator.pop(context, 'leave'),
            child: const Text('Leave pending'),
          ),
        ],
      ),
    );
    _asking = false;
    if (!mounted) return;
    if (decision == 'safety') SafetyAccessShell.open(context);
    if (decision == 'leave') {
      setState(() => _allowLeave = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
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
        canPop: _allowLeave || !active,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _ask();
        },
        child: widget.child,
      );
    },
  );
}
