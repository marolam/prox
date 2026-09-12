import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'meetup_live_screen.dart' as canonical;

/// Legacy constructor adapter. The canonical flow owns presence, chat, and ratings.
class MeetupLiveScreen extends StatelessWidget {
  const MeetupLiveScreen({
    super.key,
    required this.meetupId,
    required this.chatId,
    required this.aUid,
    required this.bUid,
  });
  final String meetupId;
  final String chatId;
  final String aUid;
  final String bUid;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final sessionId = chatId.trim().isEmpty ? meetupId.trim() : chatId.trim();
    if (uid == null || (uid != aUid && uid != bUid) || sessionId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Meetup')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Sign in with a participant account and open a valid meetup from your inbox.',
            ),
          ),
        ),
      );
    }
    return canonical.MeetupLiveScreen(
      chatId: sessionId,
      otherUid: uid == aUid ? bUid : aUid,
    );
  }
}
