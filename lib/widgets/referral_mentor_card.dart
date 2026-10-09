import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:prox/services/chat_service.dart';

class ReferralMentorCard extends StatelessWidget {
  const ReferralMentorCard({super.key, required this.uid, this.mentorStream});

  final String uid;
  final Stream<Map<String, dynamic>?>? mentorStream;

  Future<void> _message(BuildContext context, String mentorUid) async {
    try {
      final chatId = await ChatService.instance.ensureDirectChat(mentorUid);
      if (context.mounted) {
        Navigator.of(context).pushNamed(
          '/chat',
          arguments: {'chatId': chatId, 'otherUid': mentorUid},
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open your mentor chat. Try again or contact support.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream:
          mentorStream ??
          FirebaseFirestore.instance
              .doc('users/$uid/referralMentor/current')
              .snapshots()
              .map((doc) => doc.data()),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Your mentor contact is unavailable. Reopen Referrals or contact support.',
              ),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) return const SizedBox.shrink();
        final mentor = (data['mentorUid'] as String?) ?? '';
        if (mentor.isEmpty) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your referrer / mentor',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text((data['displayName'] as String?) ?? 'Your referrer'),
                const SizedBox(height: 8),
                const Text(
                  'An informal helper, not an official support agent. Only your direct referrer can see your referral progress and send mentor nudges. They do not see your messages or meetup details.',
                ),
                if (data['lastNudge'] is String) ...[
                  const SizedBox(height: 8),
                  Text(data['lastNudge'] as String),
                ],
                const SizedBox(height: 10),
                if (data['partyAdded'] != true)
                  const Text(
                    'A mentor Party contact is added after your profile is complete when your inviter enables it.',
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (data['partyAdded'] == true)
                      OutlinedButton.icon(
                        onPressed: () => _message(context, mentor),
                        icon: const Icon(Icons.chat_outlined),
                        label: const Text('Message mentor'),
                      ),
                    TextButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pushNamed('/support'),
                      icon: const Icon(Icons.support_agent_outlined),
                      label: const Text('Contact support'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
