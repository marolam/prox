import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prox/utils/auth_bound_stream.dart';

/// Party membership comes from server-projected mutual connections.
class PartyModeService {
  PartyModeService({
    FirebaseFirestore? firestore,
    Stream<String?> Function()? accountChanges,
    String? Function()? currentUid,
    Stream<Set<String>> Function(String uid)? approvedMembers,
  }) : _accounts =
           accountChanges ??
           (() => FirebaseAuth.instance.authStateChanges().map(
             (user) => user?.uid,
           )),
       _currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _members =
           approvedMembers ??
           ((uid) =>
               _firestoreMembers(firestore ?? FirebaseFirestore.instance, uid));

  static final PartyModeService instance = PartyModeService();
  final Stream<String?> Function() _accounts;
  final String? Function() _currentUid;
  final Stream<Set<String>> Function(String) _members;

  static Stream<Set<String>> _firestoreMembers(
    FirebaseFirestore db,
    String uid,
  ) => db
      .collection('users')
      .doc(uid)
      .collection('party')
      .where('mutual', isEqualTo: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .where(
              (doc) =>
                  doc.id != uid &&
                  doc.id != 'current' &&
                  doc.id != 'partySettings',
            )
            .map((doc) => doc.id)
            .toSet(),
      );

  Stream<Set<String>> watchApprovedPartyUids() {
    return authBoundStream<Set<String>>(
      accountChanges: _accounts(),
      currentUid: _currentUid,
      watch: (uid) => _members(uid).map((values) => Set.unmodifiable(values)),
      empty: const <String>{},
    );
  }

  /// A loaded snapshot for one-shot matching; unlike the live stream, this does
  /// not include the empty account-reset event emitted before Firestore loads.
  Future<Set<String>> loadApprovedPartyUids(String expectedUid) async {
    void checkAccount() {
      if (expectedUid.isEmpty || _currentUid() != expectedUid) {
        throw StateError('Party account changed.');
      }
    }

    checkAccount();
    final members = await _members(expectedUid).first;
    checkAccount();
    return Set.unmodifiable(members);
  }
}
