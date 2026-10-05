import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

bool meetupIsActive(Map<String, dynamic> data) =>
    const {'requested', 'accepted', 'live'}.contains(data['status']);

class MeetupProgressCard extends StatelessWidget {
  const MeetupProgressCard({super.key, required this.data, required this.uid});
  final Map<String, dynamic> data;
  final String uid;

  String _deadlineGuidance(BuildContext context, Timestamp? expiry) {
    if (expiry == null) {
      return 'This meetup is step-locked until completion or approved cancellation.';
    }
    final expiresAt = expiry.toDate();
    if (!expiresAt.isAfter(DateTime.now())) {
      return 'Session deadline passed. Automatic closure is in progress. Use Safety if you need to cancel by request now.';
    }
    final deadline = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(expiresAt));
    return 'Session deadline: $deadline. This meetup stays step-locked until completion or approved cancellation.';
  }

  @override
  Widget build(BuildContext context) {
    final status = data['status'];
    final planner = data['plannerUid'] == uid;
    final confirmed = data['locationStatus'] == 'confirmed';
    final arrived = data[data['aUid'] == uid ? 'aArrived' : 'bArrived'] == true;
    final traveling =
        data[data['aUid'] == uid ? 'aOnMyWayAt' : 'bOnMyWayAt'] != null;
    final hasPin = data['lat'] is num && data['lng'] is num;
    final (title, next) = switch (status) {
      'completed' => (
        'Meetup completed',
        'Both arrivals are confirmed. Next: tell us how the meetup went and decide whether to add each other to Party.',
      ),
      'cancelled' || 'canceled' => (
        'Meetup cancelled',
        'This meetup has ended for both people. No further travel or arrival confirmation is needed.',
      ),
      'auto_closed' || 'expired' => (
        'Meetup ended without completion',
        'The deadline passed before both arrivals were confirmed. This is recorded as unfinished, not a successful meetup.',
      ),
      'declined' => (
        'Meetup declined',
        'The request was declined. There is no active meetup to attend.',
      ),
      'requested' => (
        'Step 1 of 4 · Agree to meet',
        'Wait for the meetup request to be accepted before choosing a meeting point.',
      ),
      _ when !hasPin => (
        'Step 2 of 4 · Choose a meeting point',
        planner
            ? 'Set a pin at a clear public landmark or entrance. The other person must confirm it before you travel.'
            : 'Wait for the other person to share a pin, then review and confirm the meeting point.',
      ),
      _ when !confirmed => (
        'Step 2 of 4 · Confirm the pin',
        planner
            ? 'Your pin is shared. Wait for the other person to confirm it. Once confirmed, the meeting point is locked.'
            : 'Review the pin below. Confirm only if you agree to meet there. Once confirmed, the meeting point is locked.',
      ),
      _ when arrived => (
        'Step 4 of 4 · Waiting for their arrival',
        'Your arrival is saved. Ask the other person to confirm their arrival in Prox. Both confirmations are needed to complete the meetup.',
      ),
      _ when traveling => (
        'Step 4 of 4 · Meet and confirm arrival',
        'Follow directions to the agreed pin. When you are together, verify each other and tap Confirm my arrival. Use the arrival code below if needed.',
      ),
      _ => (
        'Step 3 of 4 · Travel to the meeting point',
        'The pin is confirmed. Tap On my way when you leave, then open directions. Opening Maps does not confirm your arrival. Return to Prox to finish.',
      ),
    };
    final expiry = data['expiresAt'] is Timestamp ? data['expiresAt'] as Timestamp : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(next),
            if (meetupIsActive(data)) ...[
              const SizedBox(height: 8),
              Text(
                _deadlineGuidance(context, expiry),
              ),
              const Text(
                'Do the exact next step shown above. Use Safety if you need to cancel by request. Unfinished sessions close automatically and do not count as completed meetups.',
              ),
              const SizedBox(height: 4),
              const Text(
                'Warning: no response or no-show can reduce trust and trigger temporary meetup lockouts.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
