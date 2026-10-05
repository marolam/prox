import "dart:convert";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:prox/services/business_mode/business_avatar_settings_service.dart";
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
      message:
          "Thanks for reaching out. I am available today and can confirm a slot quickly.",
    ),
    BusinessLeadTemplate(
      id: "quote_starter",
      title: "Quote starter",
      message:
          "I can provide a quote right away. Share a quick detail and I will send pricing options.",
    ),
    BusinessLeadTemplate(
      id: "follow_up",
      title: "Follow-up",
      message:
          "Following up in case this is still needed. I can help you get this done today.",
    ),
    BusinessLeadTemplate(
      id: "re_engage",
      title: "Re-engage",
      message:
          "Just checking back. If timing changed, I can still help when you are ready.",
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

  Future<(String message, String source)> _resolveLeadMessage({
    required BusinessLeadTemplate template,
  }) async {
    try {
      final settings = await BusinessAvatarSettingsService.instance
          .loadForCurrentUser()
          .timeout(const Duration(seconds: 5));
      final avatarReply = settings.reply.trim();
      if (settings.enabled && avatarReply.isNotEmpty) {
        return (avatarReply, "business_avatar");
      }
    } catch (_) {
      // Fall back to the default template content when avatar settings are unavailable.
    }
    return (template.message, "template_default");
  }

  String _followupId(String leadId, String step) =>
      "followup_${base64Url.encode(utf8.encode(jsonEncode(<String>[leadId, step]))).replaceAll('=', '')}";

  String _requireLeadId(String value) {
    final clean = value.trim();
    if (clean.isEmpty || clean.length > 160 || clean.contains("/")) {
      throw StateError("A valid leadId is required.");
    }
    return clean;
  }

  Future<void> applyTemplate({
    required String leadId,
    required String templateId,
    String channel = "in_app",
    String? threadId,
  }) async {
    final guard = await BusinessEntitlementGuard.instance
        .ensureCanOperateBusiness();
    final cleanLeadId = _requireLeadId(leadId);
    final cleanTemplateId = templateId.trim();
    if (cleanLeadId.isEmpty || cleanTemplateId.isEmpty) {
      throw StateError("leadId and templateId are required.");
    }

    final tpl = templates
        .where((t) => t.id == cleanTemplateId)
        .cast<BusinessLeadTemplate?>()
        .firstWhere((t) => t != null, orElse: () => null);
    if (tpl == null) {
      throw StateError("Unknown template: $cleanTemplateId");
    }
    final (resolvedMessage, messageSource) = await _resolveLeadMessage(
      template: tpl,
    );

    BusinessEntitlementGuard.instance.requireSignedInUid(uid: guard.uid);
    final leadRef = _leadDoc(guard.uid, cleanLeadId);
    await _fs.runTransaction((tx) async {
      BusinessEntitlementGuard.instance.requireSignedInUid(uid: guard.uid);
      final lead = await tx.get(leadRef);
      if (!lead.exists ||
          lead.data()?["deleted"] == true ||
          lead.data()?["deletedAt"] != null) {
        throw StateError("This lead is no longer available.");
      }
      tx.update(leadRef, <String, dynamic>{
        "lastTemplateId": tpl.id,
        "lastTemplateTitle": tpl.title,
        "lastTemplateMessage": resolvedMessage,
        "lastTemplateMessageSource": messageSource,
        "lastTemplateDefaultMessage": tpl.message,
        "lastTemplateChannel": channel.trim().isEmpty
            ? "in_app"
            : channel.trim(),
        "lastTemplateAt": FieldValue.serverTimestamp(),
        "templateState": "prepared",
        "updatedAt": FieldValue.serverTimestamp(),
      });
    });

    await _events(guard.uid).add(<String, dynamic>{
      "type": "business_template_prepared",
      "leadId": cleanLeadId,
      "threadId": (threadId ?? "").trim(),
      "templateId": tpl.id,
      "templateTitle": tpl.title,
      "templateMessageSource": messageSource,
      "channel": channel,
      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  Future<void> scheduleDefaultFollowups({
    required String leadId,
    String? threadId,
  }) async {
    final guard = await BusinessEntitlementGuard.instance
        .ensureCanOperateBusiness();
    final cleanLeadId = _requireLeadId(leadId);
    if (cleanLeadId.isEmpty) {
      throw StateError("leadId is required.");
    }
    const followUpTemplate = BusinessLeadTemplate(
      id: "follow_up",
      title: "Follow-up",
      message:
          "Following up in case this is still needed. I can help you get this done today.",
    );
    final (resolvedMessage, messageSource) = await _resolveLeadMessage(
      template: followUpTemplate,
    );

    final now = DateTime.now().toUtc();
    final steps = <Map<String, dynamic>>[
      <String, dynamic>{
        "step": "followup_15m",
        "delay": const Duration(minutes: 15),
      },
      <String, dynamic>{
        "step": "followup_24h",
        "delay": const Duration(hours: 24),
      },
      <String, dynamic>{
        "step": "followup_72h",
        "delay": const Duration(hours: 72),
      },
    ];

    BusinessEntitlementGuard.instance.requireSignedInUid(uid: guard.uid);
    final documents = steps
        .map(
          (step) => _automationItems(
            guard.uid,
          ).doc(_followupId(cleanLeadId, step["step"] as String)),
        )
        .toList();
    await _fs.runTransaction((tx) async {
      BusinessEntitlementGuard.instance.requireSignedInUid(uid: guard.uid);
      final lead = await tx.get(_leadDoc(guard.uid, cleanLeadId));
      final existing = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in documents) {
        existing.add(await tx.get(doc));
      }
      if (!lead.exists ||
          lead.data()?["deleted"] == true ||
          lead.data()?["deletedAt"] != null ||
          <String>[
            "won",
            "lost",
            "closed",
            "responded",
          ].contains(lead.data()?["status"])) {
        throw StateError("Follow-ups need an open lead.");
      }
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i];
        final doc = documents[i];
        if (existing[i].exists) {
          // A retry refreshes the server queue without postponing the original deadline.
          if (existing[i].data()?["state"] == "scheduled") {
            tx.update(doc, <String, dynamic>{
              "updatedAt": FieldValue.serverTimestamp(),
            });
            continue;
          }
          if (existing[i].data()?["state"] != "cancelled") continue;
        }
        final DateTime scheduledAt = now.add(step["delay"] as Duration);

        tx.set(doc, <String, dynamic>{
          "automationId": doc.id,
          "leadId": cleanLeadId,
          "threadId": (threadId ?? "").trim(),
          "state": "scheduled",
          "step": step["step"],
          "channel": "in_app",
          "templateId": "follow_up",
          "templateMessage": resolvedMessage,
          "templateMessageSource": messageSource,
          "scheduledAt": Timestamp.fromDate(scheduledAt),
          "createdAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        });
      }
    });

    await _events(
      guard.uid,
    ).doc(_followupId(cleanLeadId, "sequence")).set(<String, dynamic>{
      "type": "business_followup_scheduled",
      "leadId": cleanLeadId,
      "threadId": (threadId ?? "").trim(),
      "templateMessageSource": messageSource,
      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  Future<int> cancelScheduledFollowupsForLead({
    required String leadId,
    String reason = "customer_replied",
    String? expectedUid,
  }) async {
    // Owners can stop pending reminders even after their paid entitlement expires.
    final uid = BusinessEntitlementGuard.instance.requireSignedInUid(
      uid: expectedUid,
    );
    final cleanLeadId = _requireLeadId(leadId);
    if (cleanLeadId.isEmpty) {
      throw StateError("leadId is required.");
    }

    var totalCancelled = 0;
    while (true) {
      final query = await _automationItems(uid)
          .where("leadId", isEqualTo: cleanLeadId)
          .where("state", isEqualTo: "scheduled")
          .limit(300)
          .get();
      BusinessEntitlementGuard.instance.requireSignedInUid(uid: uid);

      if (query.docs.isEmpty) {
        break;
      }
      final count = await _fs.runTransaction((tx) async {
        BusinessEntitlementGuard.instance.requireSignedInUid(uid: uid);
        final current = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final doc in query.docs) {
          current.add(await tx.get(doc.reference));
        }
        var cancelled = 0;
        for (final doc in current) {
          if (!doc.exists || doc.data()?["state"] != "scheduled") continue;
          tx.update(doc.reference, <String, dynamic>{
            "state": "cancelled",
            "cancelReason": reason,
            "cancelledAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
          });
          cancelled++;
        }
        return cancelled;
      });
      totalCancelled += count;
    }
    if (totalCancelled == 0) return 0;
    await _events(uid).add(<String, dynamic>{
      "type": "business_followup_cancelled",
      "leadId": cleanLeadId,
      "cancelReason": reason,
      "cancelledCount": totalCancelled,
      "createdAt": FieldValue.serverTimestamp(),
    });

    return totalCancelled;
  }
}
