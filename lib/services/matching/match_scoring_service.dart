import "package:prox/services/matching/match_candidate.dart";

class MatchScoringService {
  MatchScoringService._();

  static final MatchScoringService instance = MatchScoringService._();

  List<MatchCandidate> rank(List<MatchCandidate> candidates) {
    final ranked = List<MatchCandidate>.of(candidates)
      ..sort((a, b) {
        final byMode = a.normalModePriority.compareTo(b.normalModePriority);
        if (byMode != 0) return byMode;
        final byScore = b.score().compareTo(a.score());
        if (byScore != 0) return byScore;
        return a.distanceMiles.compareTo(b.distanceMiles);
      });
    return ranked;
  }
}
