import "package:cloud_firestore/cloud_firestore.dart";

enum BusinessLeadScoreBand {
  hot,
  warm,
  cold,
}

enum BusinessLeadInboxFilter {
  open,
  hot,
  overdue,
  won,
  all,
}

class BusinessLeadInboxPolicy {
  BusinessLeadInboxPolicy._();

  static const Set<String> closedStatuses = <String>{
    "won",
    "lost",
    "cancelled",
    "canceled",
  };

  static bool isOpen(BusinessLeadRecord lead) {
    return !closedStatuses.contains(lead.status.trim().toLowerCase());
  }

  static bool isOverdue(BusinessLeadRecord lead, {DateTime? now}) {
    final DateTime? dueAt = lead.slaDueAt;
    if (dueAt == null || !isOpen(lead)) return false;
    final DateTime clock = (now ?? DateTime.now()).toUtc();
    return dueAt.toUtc().isBefore(clock);
  }

  static List<BusinessLeadRecord> apply({
    required List<BusinessLeadRecord> leads,
    required BusinessLeadInboxFilter filter,
    DateTime? now,
  }) {
    final DateTime clock = (now ?? DateTime.now()).toUtc();
    final List<BusinessLeadRecord> rows = leads.where((lead) {
      switch (filter) {
        case BusinessLeadInboxFilter.open:
          return isOpen(lead);
        case BusinessLeadInboxFilter.hot:
          return isOpen(lead) && lead.scoreBand == BusinessLeadScoreBand.hot;
        case BusinessLeadInboxFilter.overdue:
          return isOverdue(lead, now: clock);
        case BusinessLeadInboxFilter.won:
          return lead.status.trim().toLowerCase() == "won";
        case BusinessLeadInboxFilter.all:
          return true;
      }
    }).toList(growable: false);

    rows.sort((a, b) => _compareLeads(a, b, filter: filter, now: clock));
    return rows;
  }

  static int _compareLeads(
    BusinessLeadRecord a,
    BusinessLeadRecord b, {
    required BusinessLeadInboxFilter filter,
    required DateTime now,
  }) {
    final bool aOverdue = isOverdue(a, now: now);
    final bool bOverdue = isOverdue(b, now: now);
    if (aOverdue != bOverdue) return aOverdue ? -1 : 1;

    final DateTime? aDue = a.slaDueAt;
    final DateTime? bDue = b.slaDueAt;
    if (aDue != null && bDue != null) {
      final int dueOrder = aDue.compareTo(bDue);
      if (dueOrder != 0) return dueOrder;
    } else if (aDue != null) {
      return -1;
    } else if (bDue != null) {
      return 1;
    }

    if (filter == BusinessLeadInboxFilter.won) {
      final DateTime aWon = a.wonAt ?? a.updatedAt ?? a.scoredAt;
      final DateTime bWon = b.wonAt ?? b.updatedAt ?? b.scoredAt;
      final int wonOrder = bWon.compareTo(aWon);
      if (wonOrder != 0) return wonOrder;
    }

    final int scoreOrder = b.score.compareTo(a.score);
    if (scoreOrder != 0) return scoreOrder;

    final DateTime aTime = a.updatedAt ?? a.scoredAt;
    final DateTime bTime = b.updatedAt ?? b.scoredAt;
    return bTime.compareTo(aTime);
  }
}

class BusinessLeadRecord {
  const BusinessLeadRecord({
    required this.leadId,
    required this.score,
    required this.scoreBand,
    required this.scoreVersion,
    required this.scoredAt,
    required this.updatedAt,
    this.slaDueAt,
    this.qualified,
    this.estimatedValueUsd,
    this.status = "new",
    this.createdAt,
    this.respondedAt,
    this.wonAt,
  });

  final String leadId;
  final int score;
  final BusinessLeadScoreBand scoreBand;
  final String scoreVersion;
  final DateTime scoredAt;
  final DateTime? updatedAt;
  final DateTime? slaDueAt;
  final bool? qualified;
  final double? estimatedValueUsd;
  final String status;
  final DateTime? createdAt;
  final DateTime? respondedAt;
  final DateTime? wonAt;

  static DateTime? _readDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  static double? _readDouble(dynamic raw) {
    if (raw == null) return null;
    if (raw is double) return raw;
    if (raw is int) return raw.toDouble();
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim());
    return null;
  }

  factory BusinessLeadRecord.fromFirestore(Map<String, dynamic> json) {
    final String leadId = (json["leadId"] ?? "").toString().trim();
    final int score =
        (json["score"] is num) ? (json["score"] as num).toInt() : 0;
    final String scoreBandRaw =
        (json["scoreBand"] ?? "cold").toString().trim().toLowerCase();
    final BusinessLeadScoreBand scoreBand = switch (scoreBandRaw) {
      "hot" => BusinessLeadScoreBand.hot,
      "warm" => BusinessLeadScoreBand.warm,
      _ => BusinessLeadScoreBand.cold,
    };

    return BusinessLeadRecord(
      leadId: leadId,
      score: score,
      scoreBand: scoreBand,
      scoreVersion: (json["scoreVersion"] ?? "bm_v1").toString().trim(),
      scoredAt: _readDateTime(json["scoredAt"]) ?? DateTime.now().toUtc(),
      updatedAt: _readDateTime(json["updatedAt"]),
      slaDueAt: _readDateTime(json["slaDueAt"]),
      qualified: json["qualified"] is bool ? json["qualified"] as bool : null,
      estimatedValueUsd: _readDouble(json["estimatedValueUsd"]),
      status: (json["status"] ?? "new").toString().trim().toLowerCase(),
      createdAt: _readDateTime(json["createdAt"]),
      respondedAt: _readDateTime(json["respondedAt"]),
      wonAt: _readDateTime(json["wonAt"]),
    );
  }
}

class BusinessLeadScoringSignals {
  const BusinessLeadScoringSignals({
    this.leadAgeMinutes = 0,
    this.intentKeywordOverlap = 0,
    this.distanceKm,
    this.profileCompleteness = 0,
    this.recentEngagementCount = 0,
  });

  final int leadAgeMinutes;
  final int intentKeywordOverlap;
  final double? distanceKm;
  final double profileCompleteness; // 0.0 - 1.0
  final int recentEngagementCount;
}

class BusinessLeadScore {
  const BusinessLeadScore({
    required this.score,
    required this.band,
    required this.scoreVersion,
    required this.scoredAt,
  });

  final int score;
  final BusinessLeadScoreBand band;
  final String scoreVersion;
  final DateTime scoredAt;

  Map<String, dynamic> toFirestoreJson() {
    return <String, dynamic>{
      "score": score,
      "scoreBand": band.name,
      "scoreVersion": scoreVersion,
      "scoredAt": scoredAt.toIso8601String(),
    };
  }
}
