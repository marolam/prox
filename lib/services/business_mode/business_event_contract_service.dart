import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

class BusinessEventValidationIssue {
  const BusinessEventValidationIssue({
    required this.docId,
    required this.type,
    required this.missingFields,
  });

  final String docId;
  final String type;
  final List<String> missingFields;
}

class BusinessEventValidationSummary {
  const BusinessEventValidationSummary({
    required this.totalEvents,
    required this.validEvents,
    required this.invalidEvents,
    required this.issues,
    required this.seenTypes,
    required this.expectedTypes,
  });

  final int totalEvents;
  final int validEvents;
  final int invalidEvents;
  final List<BusinessEventValidationIssue> issues;
  final Set<String> seenTypes;
  final Set<String> expectedTypes;

  List<String> get missingExpectedTypes {
    return expectedTypes.where((t) => !seenTypes.contains(t)).toList(growable: false);
  }
}

class BusinessEventContractService {
  BusinessEventContractService._();
  static final BusinessEventContractService instance =
      BusinessEventContractService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  static const Map<String, List<String>> requiredFieldsByType =
      <String, List<String>>{
    "business_lead_scored": <String>["leadId", "score", "scoreBand", "createdAt"],
    "business_template_applied": <String>["leadId", "templateId", "channel", "createdAt"],
    "business_followup_scheduled": <String>["leadId", "createdAt"],
    "business_followup_cancelled": <String>["leadId", "cancelReason", "createdAt"],
    "business_followup_sent": <String>["leadId", "step", "channel", "createdAt"],
    "business_roi_recomputed": <String>["leadsReceived", "paybackRatio", "createdAt"],
  };

  Stream<BusinessEventValidationSummary> watchSummary({int limit = 200}) {
    final uid = (_auth.currentUser?.uid ?? "").trim();
    if (uid.isEmpty) {
      return Stream.value(
        BusinessEventValidationSummary(
          totalEvents: 0,
          validEvents: 0,
          invalidEvents: 0,
          issues: const <BusinessEventValidationIssue>[],
          seenTypes: <String>{},
          expectedTypes: requiredFieldsByType.keys.toSet(),
        ),
      );
    }

    return _fs
        .collection("users")
        .doc(uid)
        .collection("business")
        .doc("events")
        .collection("items")
        .orderBy("createdAt", descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      int total = 0;
      int valid = 0;
      int invalid = 0;
      final Set<String> seen = <String>{};
      final List<BusinessEventValidationIssue> issues = <BusinessEventValidationIssue>[];

      for (final doc in snap.docs) {
        final data = doc.data();
        final type = (data["type"] ?? "").toString().trim();
        if (type.isEmpty) {
          invalid++;
          issues.add(
            BusinessEventValidationIssue(
              docId: doc.id,
              type: "unknown",
              missingFields: const <String>["type"],
            ),
          );
          continue;
        }

        total++;
        seen.add(type);

        final required = requiredFieldsByType[type] ?? const <String>[];
        if (required.isEmpty) {
          valid++;
          continue;
        }

        final List<String> missing = <String>[];
        for (final field in required) {
          if (!data.containsKey(field) || data[field] == null) {
            missing.add(field);
            continue;
          }
          if (data[field] is String && (data[field] as String).trim().isEmpty) {
            missing.add(field);
          }
        }

        if (missing.isEmpty) {
          valid++;
        } else {
          invalid++;
          issues.add(
            BusinessEventValidationIssue(
              docId: doc.id,
              type: type,
              missingFields: missing,
            ),
          );
        }
      }

      return BusinessEventValidationSummary(
        totalEvents: total,
        validEvents: valid,
        invalidEvents: invalid,
        issues: issues,
        seenTypes: seen,
        expectedTypes: requiredFieldsByType.keys.toSet(),
      );
    });
  }
}
