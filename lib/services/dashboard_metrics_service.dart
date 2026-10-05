import "package:prox/models/dashboard_metrics.dart";
import "package:cloud_firestore/cloud_firestore.dart";

class DashboardMetricsService {
  DashboardMetricsService._();
  DashboardMetricsService.forTesting(FirebaseFirestore firestore)
    : _firestore = firestore;
  FirebaseFirestore? _firestore;

  static final DashboardMetricsService instance = DashboardMetricsService._();

  Stream<DashboardMetrics?> watchMetrics() =>
      (_firestore ?? FirebaseFirestore.instance)
          .doc('dashboard/metrics')
          .snapshots()
          .map(
            (snapshot) => snapshot.exists
                ? DashboardMetrics.fromFirestore(snapshot.data()!)
                : null,
          );
}
