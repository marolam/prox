import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SafetySession {
  const SafetySession({
    required this.id,
    required this.otherUid,
    required this.hasMeetup,
    required this.hasChat,
    this.isGroup = false,
  });
  final String id;
  final String otherUid;
  final bool hasMeetup;
  final bool hasChat;
  final bool isGroup;
}

class SafetySessionService {
  static Stream<List<SafetySession>> watch(String uid) {
    final db = FirebaseFirestore.instance;
    final chats = <String, Map<String, dynamic>>{};
    final a = <String, Map<String, dynamic>>{};
    final b = <String, Map<String, dynamic>>{};
    final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    late StreamController<List<SafetySession>> controller;
    void emit() {
      final meetups = {...a, ...b};
      final result = <SafetySession>[];
      for (final id in {...chats.keys, ...meetups.keys}) {
        final chat = chats[id];
        final meetup = meetups[id];
        final activeMeetup = const {
          'requested',
          'accepted',
          'live',
        }.contains(meetup?['status']);
        final gate = chat?['chatGate'];
        final activeChat =
            chat != null &&
            chat['closedAt'] == null &&
            (gate is! Map ||
                !const {'expired', 'declined'}.contains(gate['status']));
        if (!activeMeetup && !activeChat) continue;
        final participants = chat?['participants'];
        final other = activeMeetup
            ? (meetup!['aUid'] == uid ? meetup['bUid'] : meetup['aUid'])
            : (participants is List
                  ? participants.where((p) => p != uid).firstOrNull
                  : '');
        result.add(
          SafetySession(
            id: id,
            otherUid: '$other',
            hasMeetup: activeMeetup,
            hasChat: activeChat,
            isGroup:
                chat?['isGroup'] == true ||
                (participants is List && participants.length > 2),
          ),
        );
      }
      result.sort(
        (x, y) => (y.hasMeetup ? 1 : 0).compareTo(x.hasMeetup ? 1 : 0),
      );
      controller.add(result);
    }

    void listen(
      Query<Map<String, dynamic>> query,
      Map<String, Map<String, dynamic>> target,
    ) {
      subs.add(
        query.snapshots().listen(
          (snap) {
            target
              ..clear()
              ..addEntries(snap.docs.map((d) => MapEntry(d.id, d.data())));
            emit();
          },
          onError: (Object error, StackTrace stack) =>
              controller.addError(error, stack),
        ),
      );
    }

    controller = StreamController<List<SafetySession>>(
      onListen: () {
        listen(
          db.collection('chats').where('participants', arrayContains: uid),
          chats,
        );
        listen(db.collection('meetups').where('aUid', isEqualTo: uid), a);
        listen(db.collection('meetups').where('bUid', isEqualTo: uid), b);
      },
      onCancel: () async {
        for (final sub in subs) {
          await sub.cancel();
        }
      },
    );
    return controller.stream;
  }

  static Future<void> end(String chatId, {required bool endChat}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to end this session.');
    await FirebaseFunctions.instance
        .httpsCallable(
          'endMySafetySession',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call<void>({'chatId': chatId, 'endChat': endChat});
    if (FirebaseAuth.instance.currentUser?.uid != uid)
      throw StateError('Account changed.');
  }
}
