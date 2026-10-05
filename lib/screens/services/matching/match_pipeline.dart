import "package:prox/services/geoquery_service.dart";
import "package:prox/services/matching/match_candidate.dart";
import "package:prox/services/matching/match_scoring_service.dart";
import "package:prox/services/matching/matching_runtime_service.dart";
import "package:prox/services/trust/trust_score_service.dart";
import "package:prox/models/user_settings.dart";
import "package:prox/utils/bounded_async_map.dart";

class MatchPipeline {
  MatchPipeline({Future<double> Function(String uid)? trustScoreForUid})
    : _trustScoreForUid =
          trustScoreForUid ?? TrustScoreService.instance.getTrustScore;
  static final MatchPipeline instance = MatchPipeline();
  final Future<double> Function(String uid) _trustScoreForUid;

  Future<List<MatchCandidate>> buildCandidates({
    required List<NearbyDoc> nearby,
    String myPartyId = '',
    MatchDiscoverySettings? discovery,
    Set<String>? partyMemberUids,
  }) async {
    final settings = discovery ?? const MatchDiscoverySettings.defaults();
    if (settings.modeKind == MatchingModeKind.listen) {
      // Listen is one nearby pool: neither trust reads nor Party boosts should
      // delay or prioritize its cards. Trust is not an eligibility requirement.
      return nearby
          .map(
            (n) => MatchCandidate(
              uid: n.uid,
              distanceMiles: n.distanceMiles,
              trustScore: 0.5,
              sameParty: false,
              normalModePriority: 0,
              profile: n.data,
            ),
          )
          .toList()
        ..sort((a, b) {
          final distance = a.distanceMiles.compareTo(b.distanceMiles);
          return distance != 0 ? distance : a.uid.compareTo(b.uid);
        });
    }
    final applyPartyScope =
        settings.modeKind != MatchingModeKind.listen &&
        (settings.partyScope == MatchPartyScope.partyOnly ||
            settings.partyScope == MatchPartyScope.tree ||
            settings.partyScope == MatchPartyScope.extendedOnly);
    final approvedPartyMembers =
        partyMemberUids
            ?.map((uid) => uid.trim())
            .where((uid) => uid.isNotEmpty)
            .toSet() ??
        <String>{};

    final approved = nearby.where(
      (candidate) =>
          !applyPartyScope || approvedPartyMembers.contains(candidate.uid),
    );
    final out = await boundedAsyncMap(approved, (n) async {
      final trust = await _trustScoreForUid(
        n.uid,
      ).timeout(const Duration(seconds: 5));
      final sameParty = approvedPartyMembers.contains(n.uid);
      final localMode = settings.normalMode;

      return MatchCandidate(
        uid: n.uid,
        distanceMiles: n.distanceMiles,
        trustScore: trust,
        sameParty: sameParty,
        normalModePriority:
            (settings.modeKind != MatchingModeKind.normal ||
                localMode == NormalMatchMode.active ||
                MatchingRuntimeService.normalModeForPeer(n) ==
                    NormalMatchMode.active)
            ? 0
            : 1,
        profile: n.data,
      );
    });

    return MatchScoringService.instance.rank(out);
  }
}
