import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prox/utils/auth_bound_stream.dart';

/// Party membership comes from server-projected mutual connections.
class PartyModeService {
  PartyModeService({
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
       _members = approvedMembers ?? _firestoreMembers;

  static final PartyModeService instance = PartyModeService();
  final Stream<String?> Function() _accounts;
  final String? Function() _currentUid;
  final Stream<Set<String>> Function(String) _members;

  static Stream<Set<String>> _firestoreMembers(String uid) => FirebaseFirestore
      .instance
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
}
