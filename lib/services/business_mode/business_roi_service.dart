import "package:cloud_firestore/cloud_firestore.dart";
import "package:prox/models/business_lead_models.dart";
import "package:prox/services/business_mode/business_entitlement_guard.dart";

class BusinessRoiSummary {
  const BusinessRoiSummary({
    required this.leadsReceived,
    required this.qualifiedLeads,
    required this.wonLeads,
    required this.responseUnderSla,
    required this.revenueInfluencedUsd,
    required this.monthlySubscriptionUsd,
  });

  final int leadsReceived;
  final int qualifiedLeads;
  final int wonLeads;
  final int responseUnderSla;
  final double revenueInfluencedUsd;
  final double monthlySubscriptionUsd;

  double get paybackRatio {
    if (monthlySubscriptionUsd <= 0) return 0;
    return revenueInfluencedUsd / monthlySubscriptionUsd;
  }

  double get paybackNetUsd => revenueInfluencedUsd - monthlySubscriptionUsd;
}

class BusinessRoiService {
  BusinessRoiService._();
  static final BusinessRoiService instance = BusinessRoiService._();

  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  BusinessRoiSummary summarize({
    required List<BusinessLeadRecord> leads,
    required double monthlySubscriptionUsd,
  }) {
    int qualified = 0;
    int won = 0;
    int responseUnderSla = 0;
    double influencedRevenue = 0;

    for (final lead in leads) {
      final bool leadQualified = lead.qualified == true;
      final bool leadWon = lead.status == "won";
      if (leadQualified) qualified++;
      if (leadWon) won++;

      if (lead.respondedAt != null && lead.slaDueAt != null) {
        if (!lead.respondedAt!.toUtc().isAfter(lead.slaDueAt!.toUtc())) {
          responseUnderSla++;
        }
      }

      final value = lead.estimatedValueUsd ?? 0;
      if (leadWon) {
        influencedRevenue += value;
      } else if (leadQualified) {
        influencedRevenue += value * 0.5;
      }
    }

    return BusinessRoiSummary(
      leadsReceived: leads.length,
      qualifiedLeads: qualified,
      wonLeads: won,
      responseUnderSla: responseUnderSla,
      revenueInfluencedUsd: influencedRevenue,
      monthlySubscriptionUsd: monthlySubscriptionUsd,
    );
  }

  Future<void> writeSnapshot({
    required List<BusinessLeadRecord> leads,
    required double monthlySubscriptionUsd,
    String? uid,
  }) async {
    final guard = await BusinessEntitlementGuard.instance.ensureCanOperateBusiness(uid: uid);
    final summary = summarize(
      leads: leads,
      monthlySubscriptionUsd: monthlySubscriptionUsd,
    );

    await _fs
        .collection("users")
        .doc(guard.uid)
        .collection("business")
        .doc("roi")
        .collection("items")
        .doc("summary")
        .set(<String, dynamic>{
      "leadsReceived": summary.leadsReceived,
      "qualifiedLeads": summary.qualifiedLeads,
      "wonLeads": summary.wonLeads,
      "responseUnderSla": summary.responseUnderSla,
      "revenueInfluencedUsd": summary.revenueInfluencedUsd,
      "monthlySubscriptionUsd": summary.monthlySubscriptionUsd,
      "paybackRatio": summary.paybackRatio,
      "paybackNetUsd": summary.paybackNetUsd,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _fs
        .collection("users")
        .doc(guard.uid)
        .collection("business")
        .doc("events")
        .collection("items")
        .add(<String, dynamic>{
      "type": "business_roi_recomputed",
      "leadsReceived": summary.leadsReceived,
      "qualifiedLeads": summary.qualifiedLeads,
      "wonLeads": summary.wonLeads,
      "revenueInfluencedUsd": summary.revenueInfluencedUsd,
      "paybackRatio": summary.paybackRatio,
      "paybackNetUsd": summary.paybackNetUsd,
      "createdAt": FieldValue.serverTimestamp(),
    });
  }
}
