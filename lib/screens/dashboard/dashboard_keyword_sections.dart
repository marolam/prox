import 'package:prox/models/dashboard_metrics.dart';

String _normalizeKeywordLabel(String raw) {
  return raw.trim().replaceAll(RegExp(r'\s+'), ' ');
}

List<KeywordMetric> _sanitizeTopKeywords(List<KeywordMetric> input) {
  final out = <KeywordMetric>[];
  final seen = <String>{};

  for (final item in input) {
    final keyword = _normalizeKeywordLabel(item.keyword);
    if (keyword.isEmpty || item.count <= 0) continue;

    final key = keyword.toLowerCase();
    if (!seen.add(key)) continue;

    out.add(KeywordMetric(keyword: keyword, count: item.count, delta: item.delta));
  }

  return out;
}

List<KeywordMetric> _sanitizeTrendingKeywords(List<KeywordMetric> input) {
  final out = <KeywordMetric>[];
  final seen = <String>{};

  for (final item in input) {
    final keyword = _normalizeKeywordLabel(item.keyword);
    if (keyword.isEmpty || item.delta <= 0) continue;

    final key = keyword.toLowerCase();
    if (!seen.add(key)) continue;

    out.add(KeywordMetric(keyword: keyword, count: item.count, delta: item.delta));
  }

  return out;
}

class DashboardKeywordSections {
  const DashboardKeywordSections({
    required this.showLiveData,
    required this.topKeywords,
    required this.trendingKeywords,
  });

  final bool showLiveData;
  final List<KeywordMetric> topKeywords;
  final List<KeywordMetric> trendingKeywords;
}

DashboardKeywordSections resolveDashboardKeywordSections(
  DashboardMetrics? metrics,
) {
  if (metrics == null || metrics.updatedAt == null) {
    return const DashboardKeywordSections(
      showLiveData: false,
      topKeywords: <KeywordMetric>[],
      trendingKeywords: <KeywordMetric>[],
    );
  }

  return DashboardKeywordSections(
    showLiveData: true,
    topKeywords: _sanitizeTopKeywords(metrics.topKeywords),
    trendingKeywords: _sanitizeTrendingKeywords(metrics.trendingKeywords),
  );
}
