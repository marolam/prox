import "package:prox/services/matching/match_candidate.dart";

class MatchScoringService {
  MatchScoringService._();

  static final MatchScoringService instance = MatchScoringService._();

  List<MatchCandidate> rank(List<MatchCandidate> candidates) {
    final ranked = List<MatchCandidate>.of(candidates)
      ..sort((a, b) => b.score().compareTo(a.score()));
    return ranked;
  }
}