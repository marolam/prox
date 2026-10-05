import 'package:flutter_test/flutter_test.dart';
import 'package:prox/models/dashboard_metrics.dart';
import 'package:prox/screens/dashboard/dashboard_keyword_sections.dart';

void main() {
  test('returns hidden keyword sections when metrics are null', () {
    final sections = resolveDashboardKeywordSections(null);

    expect(sections.showLiveData, isFalse);
    expect(sections.topKeywords, isEmpty);
    expect(sections.trendingKeywords, isEmpty);
  });

  test('returns hidden keyword sections when metrics have no live timestamp', () {
    const metrics = DashboardMetrics(
      topKeywords: <KeywordMetric>[
        KeywordMetric(keyword: 'placeholder-top', count: 9),
      ],
      trendingKeywords: <KeywordMetric>[
        KeywordMetric(keyword: 'placeholder-trending', count: 0, delta: 2),
      ],
    );

    final sections = resolveDashboardKeywordSections(metrics);

    expect(sections.showLiveData, isFalse);
    expect(sections.topKeywords, isEmpty);
    expect(sections.trendingKeywords, isEmpty);
  });

  test('returns live keyword sections when metrics include updatedAt', () {
    final metrics = DashboardMetrics(
      updatedAt: DateTime.utc(2026, 9, 25, 12),
      topKeywords: const <KeywordMetric>[
        KeywordMetric(keyword: 'flat tire help', count: 12),
      ],
      trendingKeywords: const <KeywordMetric>[
        KeywordMetric(keyword: 'bike repair', count: 0, delta: 4),
      ],
    );

    final sections = resolveDashboardKeywordSections(metrics);

    expect(sections.showLiveData, isTrue);
    expect(sections.topKeywords.single.keyword, 'flat tire help');
    expect(sections.trendingKeywords.single.keyword, 'bike repair');
  });

  test('filters invalid and duplicate keyword rows before showing live data', () {
    final metrics = DashboardMetrics(
      updatedAt: DateTime.utc(2026, 9, 26, 9),
      topKeywords: const <KeywordMetric>[
        KeywordMetric(keyword: '  ', count: 9),
        KeywordMetric(keyword: 'flat tire help', count: 0),
        KeywordMetric(keyword: '  flat   tire  help ', count: 12),
        KeywordMetric(keyword: 'Flat tire help', count: 18),
        KeywordMetric(keyword: 'bike repair', count: 4),
      ],
      trendingKeywords: const <KeywordMetric>[
        KeywordMetric(keyword: '', count: 0, delta: 3),
        KeywordMetric(keyword: 'roadside assist', count: 0, delta: 0),
        KeywordMetric(keyword: '  bike   repair ', count: 0, delta: 3),
        KeywordMetric(keyword: 'Bike repair', count: 0, delta: 5),
        KeywordMetric(keyword: 'jump start', count: 0, delta: 2),
      ],
    );

    final sections = resolveDashboardKeywordSections(metrics);

    expect(sections.showLiveData, isTrue);
    expect(
      sections.topKeywords.map((k) => k.keyword).toList(growable: false),
      equals(<String>['flat tire help', 'bike repair']),
    );
    expect(
      sections.trendingKeywords.map((k) => k.keyword).toList(growable: false),
      equals(<String>['bike repair', 'jump start']),
    );
  });
}
