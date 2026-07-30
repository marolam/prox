class TrustScoreService {
  TrustScoreService._();

  static final TrustScoreService instance = TrustScoreService._();

  Future<double> getTrustScore(String uid) async => 0.5;
}