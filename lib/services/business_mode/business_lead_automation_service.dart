import "package:cloud_firestore/cloud_firestore.dart";
import "package:prox/services/business_mode/business_entitlement_guard.dart";

class BusinessLeadTemplate {
  const BusinessLeadTemplate({
    required this.id,
    required this.title,
    required this.message,
  });

  final String id;
  final String title;
  final String message;
}

class BusinessLeadAutomationService {
  BusinessLeadAutomationService._();
  static final BusinessLeadAutomationService instance =
      BusinessLeadAutomationService._();

  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  static const List<BusinessLeadTemplate> templates = <BusinessLeadTemplate>[
    BusinessLeadTemplate(
      id: "availability",
      title: "Availability",
      message: "Thanks for reaching out. I am available today and can confirm a slot quickly.",
    ),
    BusinessLeadTemplate(
      id: "quote_starter",
      title: "Quote starter",
      message: "I can provide a quote right away. Share a quick detail and I will send pricing options.",
    ),
    BusinessLeadTemplate(
      id: "follow_up",
      title: "Follow-up",
      message: "Following up in case this is still needed. I can help you get this done today.",
    ),
    BusinessLeadTemplate(
      id: "re_engage",
      title: "Re-engage",
      message: "Just checking back. If timing changed, I can still help when you are ready.",
    ),
  ];

  CollectionReference<Map<String, dynamic>> _automationItems(String uid) {
    return _fs
        .collection("users")
        .doc(uid)
        .collection("business")
        .doc("automations")
        .collection("items");
  }

  DocumentReference<Map<String, dynamic>> _leadDoc(String uid, String leadId) {
    return _fs
        .collection("users")
        .doc(uid)
        .collection("business")
        .doc("leads")
        .collection("items")
        .doc(leadId);
  }

  CollectionReference<Map<String, dynamic>> _events(String uid) {
    return _fs
        .collection("users")
        .doc(uid)
        .collection("business")
        .doc("events")
        .collection("items");
  }

  Future<void> applyTemplate({
    required String leadId,
    required String templateId,
    String channel = "in_app",
    String? threadId,
  }) async {
    final guard = await BusinessEntitlementGuard.instance.ensureCanOperateBusiness();
    final cleanLeadId = leadId.trim();
    final cleanTemplateId = templateId.trim();
    if (cleanLeadId.isEmpty || cleanTemplateId.isEmpty) {
      throw StateError("leadId and templateId are required.");
    }

    final tpl = templates.where((t) => t.id == cleanTemplateId).cast<BusinessLeadTemplate?>().firstWhere(
          (t) => t != null,
          orElse: () => null,
        );
    if (tpl == null) {
      throw StateError("Unknown template: $cleanTemplateId");
    }

    await _leadDoc(guard.uid, cleanLeadId).set(<String, dynamic>{
      "lastTemplateId": tpl.id,
      "lastTemplateTitle": tpl.title,
      "lastTemplateMessage": tpl.message,
      "lastTemplateChannel": channel.trim().isEmpty ? "in_app" : channel.trim(),
      "lastTemplateAt": FieldValue.serverTimestamp(),
      "status": "responded",
      "respondedAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _events(guard.uid).add(<String, dynamic>{
      "type": "business_template_applied",
      "leadId": cleanLeadId,
      "threadId": (threadId ?? "").trim(),
      "templateId": tpl.id,
      "templateTitle": tpl.title,
      "channel": channel,
      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  Future<void> scheduleDefaultFollowups({
    required String leadId,
    String? threadId,
  }) async {
    final guard = await BusinessEntitlementGuard.instance.ensureCanOperateBusiness();
    final cleanLeadId = leadId.trim();
    if (cleanLeadId.isEmpty) {
      throw StateError("leadId is required.");
    }

    final now = DateTime.now().toUtc();
    final steps = <Map<String, dynamic>>[
      <String, dynamic>{"step": "followup_15m", "delay": const Duration(minutes: 15)},
      <String, dynamic>{"step": "followup_24h", "delay": const Duration(hours: 24)},
      <String, dynamic>{"step": "followup_72h", "delay": const Duration(hours: 72)},
    ];

    final batch = _fs.batch();
    for (final step in steps) {
      final doc = _automationItems(guard.uid).doc();
      final DateTime scheduledAt = now.add(step["delay"] as Duration);

      batch.set(doc, <String, dynamic>{
        "automationId": doc.id,
        "leadId": cleanLeadId,
        "threadId": (threadId ?? "").trim(),
        "state": "scheduled",
        "step": step["step"],
        "channel": "in_app",
        "templateId": "follow_up",
        "scheduledAt": Timestamp.fromDate(scheduledAt),
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    await _events(guard.uid).add(<String, dynamic>{
      "type": "business_followup_scheduled",
      "leadId": cleanLeadId,
      "threadId": (threadId ?? "").trim(),
      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  Future<int> cancelScheduledFollowupsForLead({
    required String leadId,
    String reason = "customer_replied",
  }) async {
    final guard = await BusinessEntitlementGuard.instance.ensureCanOperateBusiness();
    final cleanLeadId = leadId.trim();
    if (cleanLeadId.isEmpty) {
      throw StateError("leadId is required.");
    }

    final query = await _automationItems(guard.uid)
        .where("leadId", isEqualTo: cleanLeadId)
        .where("state", isEqualTo: "scheduled")
        .get();

    if (query.docs.isEmpty) {
      return 0;
    }

    final batch = _fs.batch();
    for (final doc in query.docs) {
      batch.set(doc.reference, <String, dynamic>{
        "state": "cancelled",
        "cancelReason": reason,
        "cancelledAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();

    await _events(guard.uid).add(<String, dynamic>{
      "type": "business_followup_cancelled",
      "leadId": cleanLeadId,
      "cancelReason": reason,
      "cancelledCount": query.docs.length,
      "createdAt": FieldValue.serverTimestamp(),
    });

    return query.docs.length;
  }
}
