class MatchCandidate {
  const MatchCandidate({
    required this.uid,
    required this.distanceMiles,
    required this.trustScore,
    required this.sameParty,
    required this.profile,
  });

  final String uid;
  final double distanceMiles;
  final double trustScore;
  final bool sameParty;
  final Map<String, dynamic> profile;

  int score() {
    final base = (trustScore * 100).round();
    final partyBoost = sameParty ? 10 : 0;
    return (base + partyBoost).clamp(0, 140);
  }
}