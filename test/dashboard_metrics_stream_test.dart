import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/models/dashboard_metrics.dart';
import 'package:prox/services/dashboard_metrics_service.dart';

void main() {
  test(
    'real metrics stream distinguishes missing snapshots, updates and genuine zero',
    () async {
      final firestore = FakeFirebaseFirestore();
      final iterator = StreamIterator(
        DashboardMetricsService.forTesting(firestore).watchMetrics(),
      );
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, isNull);
      final now = DateTime.utc(2026, 10, 5, 12);
      await firestore.doc('dashboard/metrics').set({
        'totalUsers': 43,
        'newUsersToday': 0,
        'updatedAt': Timestamp.fromDate(now),
        'topKeywords': [
          {'keyword': 'local help', 'count': 9},
        ],
      });
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current!.totalUsers, 43);
      expect(iterator.current!.newUsersToday, 0);
      expect(
        iterator.current!.hasCurrentMetric('newUsersToday', now: now),
        isTrue,
      );
      expect(
        iterator.current!.hasCurrentMetric(
          'totalSupportPointsPaidOut',
          now: now,
        ),
        isFalse,
      );
      expect(iterator.current!.topKeywords.single.count, 9);
      await firestore.doc('dashboard/metrics').update({'totalUsers': 44});
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current!.totalUsers, 44);
      await firestore.doc('dashboard/metrics').delete();
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, isNull);
      await iterator.cancel();
    },
  );

  test(
    'old snapshots retain metadata but cannot be presented as current zero counts',
    () {
      final clock = DateTime.utc(2026, 10, 5, 12);
      final metrics = DashboardMetrics.fromFirestore({
        'totalUsers': 8,
        'newUsersToday': 0,
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 4, 10, 8, 42)),
      });
      expect(metrics.totalUsers, 8);
      expect(metrics.updatedAt, DateTime.utc(2026, 4, 10, 8, 42).toLocal());
      expect(metrics.isFresh(now: clock), isFalse);
      expect(metrics.hasCurrentMetric('newUsersToday', now: clock), isFalse);
    },
  );

  test(
    'daily metrics from a fresh previous UTC date do not claim to describe today',
    () {
      final metrics = DashboardMetrics.fromFirestore({
        'totalUsers': 8,
        'newUsersToday': 4,
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 10, 4, 23, 30)),
      });
      final clock = DateTime.utc(2026, 10, 5, 0, 30);
      expect(metrics.hasCurrentMetric('totalUsers', now: clock), isTrue);
      expect(metrics.hasCurrentMetric('newUsersToday', now: clock), isFalse);
    },
  );

  test(
    'missing or malformed numeric fields are unavailable while valid zero stays available',
    () {
      final clock = DateTime.utc(2026, 10, 5, 12);
      final metrics = DashboardMetrics.fromFirestore({
        'totalUsers': '43',
        'newUsersToday': 0,
        'activeUsers': 'broken',
        'totalPointsPaidOut': -1,
        'geofenceCoverageRatio': double.nan,
        'updatedAt': Timestamp.fromDate(clock),
        'trendingKeywords': [
          {'keyword': 'repair', 'delta': 2},
        ],
      });
      expect(metrics.hasCurrentMetric('totalUsers', now: clock), isTrue);
      expect(metrics.hasCurrentMetric('newUsersToday', now: clock), isTrue);
      expect(metrics.hasCurrentMetric('activeUsers', now: clock), isFalse);
      expect(
        metrics.hasCurrentMetric('totalPointsPaidOut', now: clock),
        isFalse,
      );
      expect(
        metrics.hasCurrentMetric('geofenceCoverageRatio', now: clock),
        isFalse,
      );
      expect(metrics.trendingKeywords.single.delta, 2);
      expect(metrics.trendingKeywords.single.count, 0);
    },
  );
}
