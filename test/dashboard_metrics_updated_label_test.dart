import 'package:flutter_test/flutter_test.dart';
import 'package:prox/screens/dashboard/dashboard_metrics_updated_label.dart';

void main() {
  test('formats recent dashboard updates as just now', () {
    final now = DateTime.utc(2026, 9, 26, 12, 0, 30);
    final updatedAt = DateTime.utc(2026, 9, 26, 12, 0, 0);

    final label = formatDashboardMetricsUpdatedLabel(
      updatedAt: updatedAt,
      now: now,
    );

    expect(label, 'Updated just now');
  });

  test('formats dashboard updates in minutes and hours', () {
    final now = DateTime.utc(2026, 9, 26, 12, 0, 0);

    expect(
      formatDashboardMetricsUpdatedLabel(
        updatedAt: DateTime.utc(2026, 9, 26, 11, 51, 0),
        now: now,
      ),
      'Updated 9m ago',
    );

    expect(
      formatDashboardMetricsUpdatedLabel(
        updatedAt: DateTime.utc(2026, 9, 26, 9, 15, 0),
        now: now,
      ),
      'Updated 2h ago',
    );
  });

  test('formats dashboard updates in days before date fallback', () {
    final now = DateTime.utc(2026, 9, 26, 12, 0, 0);

    final label = formatDashboardMetricsUpdatedLabel(
      updatedAt: DateTime.utc(2026, 9, 24, 10, 0, 0),
      now: now,
    );

    expect(label, 'Updated 2d ago');
  });

  test('falls back to date/time for older dashboard updates', () {
    final now = DateTime(2026, 9, 26, 12, 0, 0);
    final updatedAt = DateTime(2026, 9, 10, 8, 5, 0);

    final label = formatDashboardMetricsUpdatedLabel(
      updatedAt: updatedAt,
      now: now,
    );

    expect(label, 'Updated 2026-09-10 08:05');
  });

  test('clamps future dashboard timestamps to just now', () {
    final now = DateTime.utc(2026, 9, 26, 12, 0, 0);
    final updatedAt = DateTime.utc(2026, 9, 26, 12, 5, 0);

    final label = formatDashboardMetricsUpdatedLabel(
      updatedAt: updatedAt,
      now: now,
    );

    expect(label, 'Updated just now');
  });
}