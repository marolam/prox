import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prox/utils/auth_bound_stream.dart';

/// Referral badges decorate confirmed Party members; they never add members.
class PartyReferralBadgeService {
  PartyReferralBadgeService({
    FirebaseFirestore? firestore,
    Stream<String?> Function()? accountChanges,
    String? Function()? currentUid,
    Stream<Map<String, dynamic>?> Function(String path)? referralDocuments,
  }) : _accounts =
           accountChanges ??
           (() => FirebaseAuth.instance.authStateChanges().map(
             (user) => user?.uid,
           )),
       _currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _documents =
           referralDocuments ??
           ((path) => (firestore ?? FirebaseFirestore.instance)
               .doc(path)
               .snapshots()
               .map((snapshot) => snapshot.data()));

  static final PartyReferralBadgeService instance = PartyReferralBadgeService();
  final Stream<String?> Function() _accounts;
  final String? Function() _currentUid;
  final Stream<Map<String, dynamic>?> Function(String) _documents;

  static List<String>? _referralPath(String path) {
    final parts = path.split('/');
    if (parts.length != 4 ||
        parts[0] != 'users' ||
        parts[2] != 'referrals' ||
        parts[1].trim().isEmpty ||
        parts[3].trim().isEmpty) {
      return null;
    }
    return parts;
  }

  static bool _verified(Map<String, dynamic> data) =>
      data['partyInPersonQrRequested'] == true &&
      data['inPersonVerified'] == true;

  static String? verifiedInviteeUid({
    required String documentPath,
    required Map<String, dynamic> data,
    required String myUid,
  }) {
    final parts = _referralPath(documentPath);
    final owner = myUid.trim();
    if (parts == null ||
        owner.isEmpty ||
        parts[1] != owner ||
        !_verified(data)) {
      return null;
    }
    // Old server-verified rows can omit uid; the canonical document ID still
    // identifies the invitee. A conflicting stored identity is never accepted.
    final uid = data['uid'] ?? parts[3];
    return uid is String && uid == parts[3] && uid != owner ? uid : null;
  }

  static String? verifiedReferrerUid({
    required String documentPath,
    required Map<String, dynamic> data,
    required String myUid,
  }) {
    final parts = _referralPath(documentPath);
    final owner = myUid.trim();
    if (parts == null ||
        owner.isEmpty ||
        parts[3] != owner ||
        parts[1] == owner ||
        data['uid'] != owner ||
        !_verified(data)) {
      return null;
    }
    return parts[1];
  }

  Stream<Set<String>> watchIncomingReferrerUids({
    required String expectedUid,
    required Iterable<String> confirmedPartyUids,
  }) {
    final owner = expectedUid.trim();
    final peers = confirmedPartyUids
        .map((uid) => uid.trim())
        .where((uid) => uid.isNotEmpty && !uid.contains('/') && uid != owner)
        .toSet();
    return authBoundStream<Set<String>>(
      accountChanges: _accounts(),
      currentUid: _currentUid,
      empty: const <String>{},
      watch: (uid) => uid == owner && owner.isNotEmpty
          ? _watchIncoming(uid, peers)
          : const Stream<Set<String>>.empty(),
    );
  }

  Stream<Set<String>> _watchIncoming(String uid, Set<String> peers) {
    return Stream<Set<String>>.multi((output) {
      final subscriptions = <StreamSubscription<Map<String, dynamic>?>>[];
      final referrers = <String>{};
      var cancelled = false;
      bool isCurrent() => !cancelled && _currentUid() == uid;
      void emit() {
        if (isCurrent()) output.add(Set<String>.unmodifiable(referrers));
      }

      emit();
      for (final peer in peers) {
        final path = 'users/$peer/referrals/$uid';
        void fail(Object error, StackTrace stack) {
          if (!isCurrent()) return;
          if (referrers.remove(peer)) emit();
          output.addError(error, stack);
        }

        try {
          subscriptions.add(
            _documents(path).listen((data) {
              if (!isCurrent()) return;
              final referrer = data == null
                  ? null
                  : verifiedReferrerUid(
                      documentPath: path,
                      data: data,
                      myUid: uid,
                    );
              final changed = referrer == null
                  ? referrers.remove(peer)
                  : referrers.add(referrer);
              if (changed) emit();
            }, onError: fail),
          );
        } catch (error, stack) {
          fail(error, stack);
        }
      }
      output.onCancel = () async {
        cancelled = true;
        await Future.wait(
          subscriptions.map((subscription) => subscription.cancel()),
        );
      };
    });
  }
}
