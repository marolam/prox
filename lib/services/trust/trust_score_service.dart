import 'package:cloud_firestore/cloud_firestore.dart';

class TrustScoreService {
  TrustScoreService._();

  static final TrustScoreService instance = TrustScoreService._();

  final Map<String, ({double score, DateTime expires})> _cache = {};

  Future<double> getTrustScore(String uid) async {
    final cached = _cache[uid];
    if (cached != null && cached.expires.isAfter(DateTime.now()))
      return cached.score;
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('stats')
        .doc('trust')
        .get();
    final data = snapshot.data();
    final positive = (data?['positive'] as num?)?.toDouble() ?? 0;
    final total = (data?['total'] as num?)?.toDouble() ?? 0;
    // A neutral prior prevents one rating from creating an extreme ranking.
    final score = ((positive + 2) / (total + 4)).clamp(0.0, 1.0);
    if (_cache.length > 500) _cache.clear();
    _cache[uid] = (
      score: score,
      expires: DateTime.now().add(const Duration(minutes: 5)),
    );
    return score;
  }
}
