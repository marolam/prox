import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:prox/models/dashboard_announcement.dart';

class DashboardAnnouncementsService {
  DashboardAnnouncementsService._();
  static final DashboardAnnouncementsService instance = DashboardAnnouncementsService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _itemsRef =>
      _db.collection('dashboard').doc('announcements').collection('items');

  Stream<List<DashboardAnnouncement>> watchActive() {
    return _itemsRef.orderBy('createdAt', descending: true).limit(30).snapshots().map((snap) {
      final out = <DashboardAnnouncement>[];
      for (final d in snap.docs) {
        final item = DashboardAnnouncement.fromDoc(d);
        if (item == null) continue;
        if (!item.active || item.isExpired) continue;
        out.add(item);
      }

      out.sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
      return out;
    });
  }

  Stream<List<Map<String, dynamic>>> watchRecentCreatedByCurrentUser() {
    final uid = _auth.currentUser?.uid ?? '';
    if (uid.isEmpty) return const Stream<List<Map<String, dynamic>>>.empty();

    return _itemsRef
        .orderBy('createdAt', descending: true)
        .limit(40)
        .snapshots()
        .map((snap) {
      final out = <Map<String, dynamic>>[];
      for (final d in snap.docs) {
        final data = d.data();
        if ((data['createdBy'] ?? '').toString().trim() != uid) continue;
        out.add(<String, dynamic>{
          'id': d.id,
          ...data,
        });
      }
      return out;
    });
  }

  Future<bool> isCurrentUserAdmin() async {
    final u = _auth.currentUser;
    if (u == null) return false;
    try {
      final token = await u.getIdTokenResult(true);
      return token.claims?['admin'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> createAnnouncement({
    required String title,
    required String body,
    bool pinned = false,
    bool broadcast = false,
    String audience = 'all',
    Duration? expiresIn,
  }) async {
    final t = title.trim();
    final b = body.trim();
    if (t.isEmpty || b.isEmpty) {
      throw StateError('Title and body are required.');
    }

    final uid = _auth.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      throw StateError('You must be signed in.');
    }

    final expiresAt = expiresIn == null
        ? null
        : Timestamp.fromDate(DateTime.now().add(expiresIn));

    await _itemsRef.add(<String, Object?>{
      'title': t,
      'body': b,
      'active': true,
      'pinned': pinned,
      'broadcast': broadcast,
      'audience': audience.trim().isEmpty ? 'all' : audience.trim(),
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (expiresAt != null) 'expiresAt': expiresAt,
    });
  }
}
