import "package:prox/services/geoquery_service.dart";
import "package:prox/services/matching/match_candidate.dart";
import "package:prox/services/matching/match_scoring_service.dart";
import "package:prox/services/matching/matching_runtime_service.dart";
import "package:prox/services/trust/trust_score_service.dart";
import "package:prox/models/user_settings.dart";
import "package:prox/models/matching_access.dart";
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
    MatchingAccessSnapshot? matchingAccess,
  }) async {
    final settings = discovery ?? const MatchDiscoverySettings.defaults();
    final access =
        matchingAccess ??
        MatchingAccessSnapshot(directUids: partyMemberUids ?? const <String>{});
    final approved = nearby.where(
      (candidate) => access.allowsPeer(
        uid: candidate.uid,
        requested: settings.partyScope,
        peerProfile: candidate.data,
      ),
    );
    Map<String, dynamic> profileFor(NearbyDoc doc) => {
      ...doc.data,
      if (access.treeMatches[doc.uid] case final connection?)
        'treeConnectionLabel': connection.label,
    };
    if (settings.modeKind == MatchingModeKind.listen) {
      // Listen keeps its keyword/intent pool and distance order while respecting
      // the same Party, Tree and public access rules as every other mode.
      return approved
          .map(
            (n) => MatchCandidate(
              uid: n.uid,
              distanceMiles: n.distanceMiles,
              trustScore: 0.5,
              sameParty: false,
              normalModePriority: 0,
              profile: profileFor(n),
            ),
          )
          .toList()
        ..sort((a, b) {
          final distance = a.distanceMiles.compareTo(b.distanceMiles);
          return distance != 0 ? distance : a.uid.compareTo(b.uid);
        });
    }
    final out = await boundedAsyncMap(approved, (n) async {
      final trust = await _trustScoreForUid(
        n.uid,
      ).timeout(const Duration(seconds: 5));
      final sameParty = access.directUids.contains(n.uid);
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
        profile: profileFor(n),
      );
    });

    return MatchScoringService.instance.rank(out);
  }
}
