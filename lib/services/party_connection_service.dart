import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PendingPartyConnection {
  const PendingPartyConnection({
    required this.otherUid,
    required this.myDecision,
    required this.theirDecision,
    required this.expiresAt,
    this.lastReminderAt,
  });
  final String otherUid;
  final String myDecision;
  final String theirDecision;
  final DateTime expiresAt;
  final DateTime? lastReminderAt;
  bool isActive(DateTime now) => expiresAt.isAfter(now);
  bool canRemind(DateTime now) =>
      myDecision == 'add' &&
      isActive(now) &&
      (lastReminderAt == null ||
          now.difference(lastReminderAt!) >= const Duration(days: 1));
  static PendingPartyConnection? fromMap(
    Map<String, dynamic> data,
    String uid,
  ) {
    final members = List<String>.from(data['members'] as List? ?? []);
    final expires = data['expiresAt'];
    if (data['status'] != 'pending' ||
        !members.contains(uid) ||
        members.length != 2 ||
        expires is! Timestamp)
      return null;
    final decisions = Map<String, dynamic>.from(
      data['decisions'] as Map? ?? {},
    );
    final reminders = Map<String, dynamic>.from(
      data['reminders'] as Map? ?? {},
    );
    final other = members.firstWhere((member) => member != uid);
    return PendingPartyConnection(
      otherUid: other,
      myDecision: decisions[uid] as String? ?? 'undecided',
      theirDecision: decisions[other] as String? ?? 'later',
      expiresAt: expires.toDate(),
      lastReminderAt: reminders[uid] is Timestamp
          ? (reminders[uid] as Timestamp).toDate()
          : null,
    );
  }
}

class PartyConnectionService {
  PartyConnectionService._();
  static final instance = PartyConnectionService._();
  Future<String> act(
    String otherUid,
    String action, {
    String? chatId,
    bool? thumb,
    String comment = '',
    String? partyDecision,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Sign in to continue.',
      );
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable(
          'respondToPartyConnection',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
        )
        .call(<String, Object?>{
          'otherUid': otherUid,
          'action': action,
          if (chatId != null) 'chatId': chatId,
          if (thumb != null) 'thumb': thumb,
          'comment': comment,
          if (partyDecision != null) 'partyDecision': partyDecision,
        });
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Your signed-in account changed. Reopen Party to continue.',
      );
    }
    return (result.data as Map)['status'] as String;
  }

  Stream<List<PendingPartyConnection>> watchPending(String uid) =>
      FirebaseFirestore.instance
          .collection('partyConnections')
          .where('members', arrayContains: uid)
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs
                    .map(
                      (doc) => PendingPartyConnection.fromMap(doc.data(), uid),
                    )
                    .whereType<PendingPartyConnection>()
                    .toList()
                  ..sort((a, b) => b.expiresAt.compareTo(a.expiresAt)),
          );
}
