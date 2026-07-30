import "package:prox/models/dashboard_metrics.dart";

class DashboardMetricsService {
  DashboardMetricsService._();

  static final DashboardMetricsService instance = DashboardMetricsService._();

  Stream<DashboardMetrics?> watchMetrics() async* {
    yield const DashboardMetrics();
  }
}