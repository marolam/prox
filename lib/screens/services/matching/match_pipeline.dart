import "package:prox/services/geoquery_service.dart";
import "package:prox/services/matching/match_candidate.dart";
import "package:prox/services/matching/match_scoring_service.dart";
import "package:prox/services/trust/trust_score_service.dart";

class MatchPipeline {
  MatchPipeline._();
  static final MatchPipeline instance = MatchPipeline._();

  Future<List<MatchCandidate>> buildCandidates({
    required List<NearbyDoc> nearby,
    required String myPartyId,
  }) async {
    final out = <MatchCandidate>[];

    for (final n in nearby) {
      final trust = await TrustScoreService.instance.getTrustScore(n.uid);
      final sameParty = myPartyId.isNotEmpty && n.data["partyId"] == myPartyId;

      out.add(
        MatchCandidate(
          uid: n.uid,
          distanceMiles: n.distanceMiles,
          trustScore: trust,
          sameParty: sameParty,
          profile: n.data,
        ),
      );
    }

    return MatchScoringService.instance.rank(out);
  }
}
