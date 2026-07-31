class KeywordMetric {
  const KeywordMetric({required this.keyword, required this.count, this.delta = 0});

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
}