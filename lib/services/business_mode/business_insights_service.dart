import 'package:firebase_auth/firebase_auth.dart';
import 'package:prox/models/business_lead_models.dart';
import 'package:prox/services/business_mode/business_lead_scoring_service.dart';

class BusinessInsightsSummary {
  const BusinessInsightsSummary({
    required this.leads,
    required this.respondedLeads,
    required this.wonLeads,
    required this.qualifiedLeads,
    required this.timedWins,
    required this.medianClose,
  });

  final int leads;
  final int respondedLeads;
  final int wonLeads;
  final int qualifiedLeads;
  final int timedWins;
  final Duration? medianClose;
  double? get responsePercent =>
      leads == 0 ? null : respondedLeads * 100 / leads;

  /// Close time needs both actual timestamps. Scoring/last-edit dates cannot
  /// substitute for creation or win evidence in older lead records.
  factory BusinessInsightsSummary.fromLeads(List<BusinessLeadRecord> records) {
    var responded = 0;
    var won = 0;
    var qualified = 0;
    final closeTimes = <int>[];
    for (final lead in records) {
      if (lead.qualified == true) qualified++;
      final created = lead.createdAt;
      final response = lead.respondedAt;
      if (response != null &&
          (created == null || !response.isBefore(created))) {
        responded++;
      }
      if (lead.status.trim().toLowerCase() != 'won') continue;
      won++;
      final win = lead.wonAt;
      if (created != null && win != null && !win.isBefore(created)) {
        closeTimes.add(win.difference(created).inMilliseconds);
      }
    }
    closeTimes.sort();
    Duration? median;
    if (closeTimes.isNotEmpty) {
      final middle = closeTimes.length ~/ 2;
      final milliseconds = closeTimes.length.isOdd
          ? closeTimes[middle]
          : ((closeTimes[middle - 1] + closeTimes[middle]) / 2).round();
      median = Duration(milliseconds: milliseconds);
    }
    return BusinessInsightsSummary(
      leads: records.length,
      respondedLeads: responded,
      wonLeads: won,
      qualifiedLeads: qualified,
      timedWins: closeTimes.length,
      medianClose: median,
    );
  }
}

abstract class BusinessInsightsRepository {
  String? get currentUid;
  Stream<String?> watchUid();
  Stream<BusinessInsightsSummary> watch(String uid);
}

class BusinessInsightsService implements BusinessInsightsRepository {
  BusinessInsightsService._();
  static final instance = BusinessInsightsService._();

  @override
  String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  Stream<String?> watchUid() =>
      FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);

  @override
  Stream<BusinessInsightsSummary> watch(String uid) async* {
    if (currentUid != uid || uid.isEmpty) {
      throw StateError('Sign in to view your business insights.');
    }
    await for (final rows in BusinessLeadScoringService.instance.watchLeads(
      uid: uid,
    )) {
      if (currentUid != uid) {
        throw StateError('Your account changed. Reopen Insights to continue.');
      }
      yield BusinessInsightsSummary.fromLeads(rows);
    }
  }
}
