import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProxPointsEventsService {
  ProxPointsEventsService._();

  static final ProxPointsEventsService instance = ProxPointsEventsService._();

  Future<void> log({
    required String kind,
    required String title,
    required int delta,
    String meta = "",
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (delta != 0)
      throw StateError('Point changes require a verified server receipt.');
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('activityEvents')
        .add({
          'kind': kind,
          'title': title,
          'delta': 0,
          'meta': meta,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }
}
