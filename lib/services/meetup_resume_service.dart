import "package:cloud_firestore/cloud_firestore.dart";

import "package:prox/services/matching/match_dashboard_session_service.dart";
import "package:prox/services/matching/matching_mode_service.dart";
import "package:prox/services/meetup_service.dart";

class MeetupResumeResult {
  final bool restored;
  final String restoredChatId;
  final int timeoutClears;

  const MeetupResumeResult({
    required this.restored,
    required this.restoredChatId,
    required this.timeoutClears,
  });
}

class MeetupResumeService {
  MeetupResumeService._();
  static final MeetupResumeService instance = MeetupResumeService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<MeetupResumeResult> recoverForUser(String uid) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) {
      MatchDashboardSessionService.instance.clear();
      return const MeetupResumeResult(restored: false, restoredChatId: "", timeoutClears: 0);
    }

    MatchDashboardSessionService.instance.clear();

    final aFuture = _db.collection("meetups").where("aUid", isEqualTo: cleanUid).limit(80).get();
    final bFuture = _db.collection("meetups").where("bUid", isEqualTo: cleanUid).limit(80).get();
    final snaps = await Future.wait([aFuture, bFuture]);

    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final d in snaps[0].docs) d.id: d,
      for (final d in snaps[1].docs) d.id: d,
    };

    int timeoutClears = 0;
    _MeetupCandidate? best;

    for (final entry in byId.entries) {
      final docId = entry.key.trim();
      if (docId.isEmpty) continue;

      final ref = MeetupService.instance.meetupRef(docId);
      var data = entry.value.data();

      final initialStatus = (data["status"] ?? "").toString().trim().toLowerCase();
      if (initialStatus == "requested") {
        await MeetupService.instance.expireMeetupRequestIfNeeded(chatId: docId);
        final refreshed = await ref.get();
        data = refreshed.data() ?? data;
      } else if (initialStatus == "live") {
        await MeetupService.instance.expireIfStale(meetupId: docId);
        final refreshed = await ref.get();
        data = refreshed.data() ?? data;
      }

      final status = (data["status"] ?? "").toString().trim().toLowerCase();
      if (_isTerminal(status)) {
        if (status == "expired") {
          timeoutClears += 1;
          final otherUid = _otherUid(myUid: cleanUid, data: data);
          try {
            await MeetupService.instance.exitAndFlushDashboards(
              chatId: docId,
              otherUid: otherUid,
              reason: "startup_timeout_reset",
            );
          } catch (_) {}
        }
        continue;
      }

      if (!_isResumable(status)) continue;

      final otherUid = _otherUid(myUid: cleanUid, data: data);
      if (otherUid.isEmpty) continue;

      final candidate = _MeetupCandidate(
        chatId: docId,
        otherUid: otherUid,
        status: status,
        updatedAtMs: _updatedAtMs(data),
      );

      if (best == null || candidate.score > best.score) {
        best = candidate;
      }
    }

    if (best != null) {
      MatchDashboardSessionService.instance.startSession(
        chatId: best.chatId,
        otherUid: best.otherUid,
        modeKind: MatchingModeService.instance.modeKind,
        normalMode: MatchingModeService.instance.normalMode,
      );
      MatchDashboardSessionService.instance.markAccepted();

      return MeetupResumeResult(
        restored: true,
        restoredChatId: best.chatId,
        timeoutClears: timeoutClears,
      );
    }

    return MeetupResumeResult(
      restored: false,
      restoredChatId: "",
      timeoutClears: timeoutClears,
    );
  }

  bool _isTerminal(String status) {
    return status == "expired" ||
        status == "cancelled" ||
        status == "declined" ||
        status == "purged" ||
        status == "auto_closed";
  }

  bool _isResumable(String status) {
    return status == "requested" ||
        status == "accepted" ||
      status == "live";
  }

  String _otherUid({required String myUid, required Map<String, dynamic> data}) {
    final aUid = (data["aUid"] ?? "").toString().trim();
    final bUid = (data["bUid"] ?? "").toString().trim();
    if (aUid == myUid) return bUid;
    if (bUid == myUid) return aUid;
    return "";
  }

  int _updatedAtMs(Map<String, dynamic> data) {
    final updated = data["updatedAt"];
    if (updated is Timestamp) return updated.millisecondsSinceEpoch;
    final completed = data["completedAt"];
    if (completed is Timestamp) return completed.millisecondsSinceEpoch;
    final started = data["startedAt"];
    if (started is Timestamp) return started.millisecondsSinceEpoch;
    return 0;
  }
}

class _MeetupCandidate {
  final String chatId;
  final String otherUid;
  final String status;
  final int updatedAtMs;

  const _MeetupCandidate({
    required this.chatId,
    required this.otherUid,
    required this.status,
    required this.updatedAtMs,
  });

  int get score {
    final base = switch (status) {
      "live" => 400000000,
      "accepted" => 300000000,
      "requested" => 200000000,
      _ => 0,
    };
    return base + updatedAtMs;
  }
}