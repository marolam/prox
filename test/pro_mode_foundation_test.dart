import "package:flutter_test/flutter_test.dart";
import "package:prox/models/pro_mode_models.dart";
import "package:prox/services/business_mode/business_mode_policy_service.dart";
import "package:prox/services/points_service.dart";

void main() {
  group("BusinessModePolicyService", () {
    PointsMeta meta({
      double trust = 80,
      int meetups = 5,
      int referrals = 5,
    }) {
      return PointsMeta(
        currentPoints: 0,
        totalPoints: 0,
        completedMeetups: meetups,
        trustPercent: trust,
        referrals: referrals,
      );
    }

    test("requires trust, meetups, and verified referrals", () {
      final service = BusinessModePolicyService.instance;

      expect(service.evaluate(meta()).eligible, isTrue);
      expect(service.evaluate(meta(trust: 79)).eligible, isFalse);
      expect(
          service.evaluate(meta(meetups: 4)).reason, contains("5 completed"));
      expect(
          service.evaluate(meta(referrals: 4)).reason, contains("5 verified"));
    });
  });

  group("ProEntity", () {
    test("serializes custodian-owned storefront foundation", () {
      final created = DateTime.utc(2026, 6, 19, 12);
      final entity = ProEntity(
        id: "pro_1",
        custodianUid: "user_1",
        displayName: "Marty Repairs",
        status: ProEntityStatus.gated,
        offerKeywords: const <String>[" Repair ", "repair", "Install"],
        audienceKeywords: const <String>["Homeowner", ""],
        serviceRadiusMiles: 80,
        priorityNotifyOptIn: true,
        createdAt: created,
        updatedAt: created,
      );

      final json = entity.toJson();

      expect(json["custodianUid"], "user_1");
      expect(json["createdBy"], "user_1");
      expect(json["offerKeywords"], <String>["repair", "install"]);
      expect(json["audienceKeywords"], <String>["homeowner"]);
      expect(json["serviceRadiusMiles"], 50);
      expect(json["priorityNotifyOptIn"], isTrue);
      expect(json["schemaVersion"], 1);
    });

    test("parses unknown or missing values into safe defaults", () {
      final entity = ProEntity.fromJson("pro_2", <String, dynamic>{
        "custodianUid": "user_2",
        "displayName": "",
        "status": "unknown",
        "qualifiedLeadCount": -4,
      });

      expect(entity.displayName, "Pro profile");
      expect(entity.status, ProEntityStatus.draft);
      expect(entity.freeTrialEligible, isTrue);
      expect(entity.qualifiedLeadCount, -4);
      expect(entity.isVisiblePreview, isTrue);
    });
  });

  group("ProKeywordSimulation", () {
    test("captures offer, audience, location, radius, and readiness output",
        () {
      final input = ProKeywordSimulationInput(
        offerKeywords: const <String>["Coffee", "events", "coffee"],
        audienceKeywords: const <String>["remote workers"],
        locationLabel: "  Downtown  ",
        radiusMiles: 0,
      );
      final result = ProKeywordSimulationResult(
        demandScore: 140,
        keywordSuggestions: const <String>["espresso", "events"],
        potentialMatchCategories: const <String>["lunch crowd"],
        setupChecklist: const <String>["Add storefront photo", ""],
      );

      expect(input.toJson()["offerKeywords"], <String>["coffee", "events"]);
      expect(input.toJson()["locationLabel"], "Downtown");
      expect(input.toJson()["radiusMiles"], 1);
      expect(result.toJson()["demandScore"], 100);
      expect(
          result.toJson()["setupChecklist"], <String>["Add storefront photo"]);
    });
  });
}
