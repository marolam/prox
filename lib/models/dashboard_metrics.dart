import 'package:cloud_firestore/cloud_firestore.dart';

class KeywordMetric {
  const KeywordMetric({
    required this.keyword,
    required this.count,
    this.delta = 0,
  });

  final String keyword;
  final int count;
  final int delta;
}

class DashboardMetrics {
  const DashboardMetrics({
    this.totalUsers = 0,
    this.newUsersToday = 0,
    this.activeUsers = 0,
    this.completedMeetups = 0,
    this.supportSessions = 0,
    this.topNeeds = const <KeywordMetric>[],
    this.risingNeeds = const <KeywordMetric>[],
    this.topKeywords = const <KeywordMetric>[],
    this.trendingKeywords = const <KeywordMetric>[],
    this.geofenceUsersCovered = 0,
    this.geofenceCoverageRatio = 0,
    this.totalPointsPaidOut = 0,
    this.totalReferralPointsPaidOut = 0,
    this.totalSupportPointsPaidOut = 0,
    this.totalBusinessModeUsers = 0,
    this.newBusinessModeUsersToday = 0,
    this.updatedAt,
    this.availableFields,
  });

  final int totalUsers;
  final int newUsersToday;
  final int activeUsers;
  final int completedMeetups;
  final int supportSessions;
  final List<KeywordMetric> topNeeds;
  final List<KeywordMetric> risingNeeds;
  final List<KeywordMetric> topKeywords;
  final List<KeywordMetric> trendingKeywords;
  final int geofenceUsersCovered;
  final double geofenceCoverageRatio;
  final int totalPointsPaidOut;
  final int totalReferralPointsPaidOut;
  final int totalSupportPointsPaidOut;
  final int totalBusinessModeUsers;
  final int newBusinessModeUsersToday;
  final DateTime? updatedAt;
  final Set<String>? availableFields;

  bool isFresh({DateTime? now}) {
    final updated = updatedAt;
    if (updated == null) return false;
    final age = (now ?? DateTime.now()).difference(updated);
    return age >= const Duration(minutes: -5) &&
        age <= const Duration(hours: 3);
  }

  bool hasCurrentMetric(String field, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    if (!isFresh(now: clock) || !(availableFields?.contains(field) ?? true))
      return false;
    if (field == 'newUsersToday' || field == 'newBusinessModeUsersToday') {
      final updated = updatedAt!.toUtc();
      final today = clock.toUtc();
      return updated.year == today.year &&
          updated.month == today.month &&
          updated.day == today.day;
    }
    return true;
  }

  factory DashboardMetrics.fromFirestore(Map<String, dynamic> data) {
    final available = <String>{};
    num? number(String field) {
      final raw = data[field];
      final value = raw is num
          ? raw
          : raw is String
          ? num.tryParse(raw)
          : null;
      if (value == null || !value.isFinite || value < 0) return null;
      available.add(field);
      return value;
    }

    int count(String field) => number(field)?.floor() ?? 0;
    List<KeywordMetric> keywords(String field) {
      final raw = data[field];
      if (raw is! List) return const <KeywordMetric>[];
      return raw
          .whereType<Map>()
          .map((row) {
            int value(dynamic input) {
              final parsed = input is num
                  ? input
                  : input is String
                  ? num.tryParse(input)
                  : null;
              return parsed != null && parsed.isFinite && parsed >= 0
                  ? parsed.floor()
                  : 0;
            }

            return KeywordMetric(
              keyword: (row['keyword'] ?? '').toString().trim(),
              count: value(row['count']),
              delta: value(row['delta']),
            );
          })
          .where((row) => row.keyword.isNotEmpty)
          .toList(growable: false);
    }

    final rawUpdated = data['updatedAt'];
    final updated = rawUpdated is Timestamp
        ? rawUpdated.toDate()
        : rawUpdated is DateTime
        ? rawUpdated
        : null;
    final totalUsers = count('totalUsers');
    final newUsersToday = count('newUsersToday');
    final activeUsers = count('activeUsers');
    final completedMeetups = count('completedMeetups');
    final supportSessions = count('supportSessions');
    final geofenceUsersCovered = count('geofenceUsersCovered');
    final coverage = number('geofenceCoverageRatio')?.toDouble() ?? 0;
    final totalPoints = count('totalPointsPaidOut');
    final referralPoints = count('totalReferralPointsPaidOut');
    final supportPoints = count('totalSupportPointsPaidOut');
    final businessUsers = count('totalBusinessModeUsers');
    final newBusinessUsers = count('newBusinessModeUsersToday');
    return DashboardMetrics(
      totalUsers: totalUsers,
      newUsersToday: newUsersToday,
      activeUsers: activeUsers,
      completedMeetups: completedMeetups,
      supportSessions: supportSessions,
      topNeeds: keywords('topNeeds'),
      risingNeeds: keywords('risingNeeds'),
      topKeywords: keywords('topKeywords'),
      trendingKeywords: keywords('trendingKeywords'),
      geofenceUsersCovered: geofenceUsersCovered,
      geofenceCoverageRatio: coverage.clamp(0, 1).toDouble(),
      totalPointsPaidOut: totalPoints,
      totalReferralPointsPaidOut: referralPoints,
      totalSupportPointsPaidOut: supportPoints,
      totalBusinessModeUsers: businessUsers,
      newBusinessModeUsersToday: newBusinessUsers,
      updatedAt: updated,
      availableFields: Set.unmodifiable(available),
    );
  }
}
