import "package:cloud_firestore/cloud_firestore.dart";
import "package:prox/models/business_lead_models.dart";
import "package:prox/services/business_mode/business_entitlement_guard.dart";
import "package:prox/services/business_mode/business_lead_automation_service.dart";
import "package:prox/services/push_notifications.dart";

class BusinessLeadScoringService {
  BusinessLeadScoringService._();
  static final BusinessLeadScoringService instance =
      BusinessLeadScoringService._();

  static const String scoreVersion = "bm_v1";

  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  int _boundInt(int value, {required int min, required int max}) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  double _boundDouble(
    double value, {
    required double min,
    required double max,
  }) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  BusinessLeadScore score(BusinessLeadScoringSignals signals) {
    final int age = _boundInt(signals.leadAgeMinutes, min: 0, max: 7 * 24 * 60);
    final int overlap = _boundInt(
      signals.intentKeywordOverlap,
      min: 0,
      max: 20,
    );
    final double completeness = _boundDouble(
      signals.profileCompleteness,
      min: 0,
      max: 1,
    );
    final int engagement = _boundInt(
      signals.recentEngagementCount,
      min: 0,
      max: 30,
    );
    final double? distance = signals.distanceKm;

    // Additive scoring baseline. Higher is better.
    int score = 20;

    // Lead age: very fresh leads are more likely to close.
    if (age <= 15) {
      score += 20;
    } else if (age <= 60) {
      score += 12;
    } else if (age <= 240) {
      score += 6;
    }

    // Intent overlap strongly predicts lead quality.
    score += _boundInt(overlap * 6, min: 0, max: 35);

    // Profile completeness offers trust signal.
    score += (completeness * 20).round();

    // Recent engagement is a lightweight conversion proxy.
    score += _boundInt(engagement * 4, min: 0, max: 20);

    // Proximity bonus when available.
    if (distance != null) {
      if (distance <= 3) {
        score += 10;
      } else if (distance <= 10) {
        score += 6;
      } else if (distance <= 25) {
        score += 2;
      }
    }

    score = _boundInt(score, min: 0, max: 100);

    final BusinessLeadScoreBand band = score >= 75
        ? BusinessLeadScoreBand.hot
        : (score >= 45
              ? BusinessLeadScoreBand.warm
              : BusinessLeadScoreBand.cold);

    return BusinessLeadScore(
      score: score,
      band: band,
      scoreVersion: scoreVersion,
      scoredAt: DateTime.now().toUtc(),
    );
  }

  Future<BusinessLeadScore> scoreAndUpsertLead({
    required String leadId,
    required BusinessLeadScoringSignals signals,
    String? uid,
    DateTime? slaDueAt,
    bool? qualified,
    double? estimatedValueUsd,
  }) async {
    final snapshot = await BusinessEntitlementGuard.instance
        .ensureCanOperateBusiness(uid: uid);
    final String cleanLeadId = leadId.trim();
    if (cleanLeadId.isEmpty) {
      throw StateError("leadId is required.");
    }

    final BusinessLeadScore computed = score(signals);

    final doc = _fs
        .collection("users")
        .doc(snapshot.uid)
        .collection("business")
        .doc("leads")
        .collection("items")
        .doc(cleanLeadId);

    await doc.set(<String, dynamic>{
      ...computed.toFirestoreJson(),
      "leadId": cleanLeadId,
      if (slaDueAt != null) "slaDueAt": slaDueAt.toUtc().toIso8601String(),
      if (qualified != null) "qualified": qualified,
      if (estimatedValueUsd != null) "estimatedValueUsd": estimatedValueUsd,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (computed.band == BusinessLeadScoreBand.hot) {
      await PushNotifications.instance.notifyBusinessHotLead(
        leadId: cleanLeadId,
        score: computed.score,
      );
    }

    await _fs
        .collection("users")
        .doc(snapshot.uid)
        .collection("business")
        .doc("events")
        .collection("items")
        .add(<String, dynamic>{
          "type": "business_lead_scored",
          "leadId": cleanLeadId,
          "score": computed.score,
          "scoreBand": computed.band.name,
          "scoreVersion": computed.scoreVersion,
          "createdAt": FieldValue.serverTimestamp(),
        });

    return computed;
  }

  Stream<List<BusinessLeadRecord>> watchLeads({String? uid}) async* {
    final snapshot = await BusinessEntitlementGuard.instance
        .ensureCanOperateBusiness(uid: uid);

    yield* _fs
        .collection("users")
        .doc(snapshot.uid)
        .collection("business")
        .doc("leads")
        .collection("items")
        .snapshots()
        .map((query) {
          final rows = query.docs
              .map((doc) => BusinessLeadRecord.fromFirestore(doc.data()))
              .toList(growable: false);

          rows.sort((a, b) {
            final int scoreOrder = b.score.compareTo(a.score);
            if (scoreOrder != 0) return scoreOrder;

            final DateTime aTime = a.updatedAt ?? a.scoredAt;
            final DateTime bTime = b.updatedAt ?? b.scoredAt;
            return bTime.compareTo(aTime);
          });

          return rows;
        });
  }

  Future<void> markLeadResponded({required String leadId, String? uid}) async {
    await _markLeadOutcome(
      leadId: leadId,
      uid: uid,
      status: "responded",
      timestampField: "respondedAt",
    );
  }

  Future<void> markLeadWon({required String leadId, String? uid}) async {
    await _markLeadOutcome(
      leadId: leadId,
      uid: uid,
      status: "won",
      timestampField: "wonAt",
    );
  }

  Future<void> _markLeadOutcome({
    required String leadId,
    required String status,
    required String timestampField,
    String? uid,
  }) async {
    final snapshot = await BusinessEntitlementGuard.instance
        .ensureCanOperateBusiness(uid: uid);
    final String cleanLeadId = leadId.trim();
    if (cleanLeadId.isEmpty ||
        cleanLeadId.length > 160 ||
        cleanLeadId.contains("/")) {
      throw StateError("A valid leadId is required.");
    }

    final doc = _fs
        .collection("users")
        .doc(snapshot.uid)
        .collection("business")
        .doc("leads")
        .collection("items")
        .doc(cleanLeadId);

    await _fs.runTransaction((tx) async {
      BusinessEntitlementGuard.instance.requireSignedInUid(uid: snapshot.uid);
      final lead = await tx.get(doc);
      BusinessEntitlementGuard.instance.requireSignedInUid(uid: snapshot.uid);
      final data = lead.data();
      if (!lead.exists ||
          data?["deleted"] == true ||
          data?["deletedAt"] != null) {
        throw StateError("This lead is no longer available.");
      }
      if (status == "responded" &&
          <String>[
            "won",
            "lost",
            "closed",
            "cancelled",
            "canceled",
          ].contains((data?["status"] ?? "").toString().toLowerCase())) {
        throw StateError("This lead is already closed.");
      }
      tx.update(doc, <String, dynamic>{
        "status": status,
        if (data?[timestampField] == null)
          timestampField: FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      });
    });
    try {
      await BusinessLeadAutomationService.instance
          .cancelScheduledFollowupsForLead(
            leadId: cleanLeadId,
            reason: status == "won" ? "lead_won" : "owner_replied",
            expectedUid: snapshot.uid,
          );
    } catch (_) {
      // The durable lead status also blocks the worker. Cancellation can be retried
      // without misreporting an already saved owner response as a failed response.
    }
  }
}
