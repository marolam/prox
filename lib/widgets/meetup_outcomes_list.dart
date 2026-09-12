import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class MeetupOutcomesList extends StatelessWidget {
  const MeetupOutcomesList({super.key, required this.uid});
  final String uid;
  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('meetupOutcomes')
        .orderBy('recordedAt', descending: true)
        .limit(30)
        .snapshots(),
    builder: (context, snap) {
      if (snap.hasError)
        return const Text('Past outcomes could not be loaded.');
      final docs = snap.data?.docs ?? [];
      return ExpansionTile(
        title: const Text('Your recent meetup outcomes'),
        subtitle: const Text('Completed, cancelled, declined, or unfinished'),
        children: [
          if (docs.isEmpty)
            const ListTile(title: Text('New outcomes will appear here.')),
          for (final doc in docs)
            ListTile(
              title: Text(switch (doc.data()['outcome']) {
                'completed' => 'Completed',
                'cancelled' => 'Cancelled · no rating penalty',
                'declined' => 'Declined',
                'unanswered' => 'Request unanswered',
                _ => 'Unfinished · no completion credit',
              }),
              subtitle: Text(
                doc.data()['recordedAt'] is Timestamp
                    ? MaterialLocalizations.of(context).formatMediumDate(
                        (doc.data()['recordedAt'] as Timestamp).toDate(),
                      )
                    : '',
              ),
            ),
        ],
      );
    },
  );
}
