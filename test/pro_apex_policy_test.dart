import "package:flutter_test/flutter_test.dart";
import "package:prox/models/pro_mode_models.dart";

void main() {
  List<ProCircleConfig> circles() => const <ProCircleConfig>[
        ProCircleConfig(
          id: "immediate",
          label: "Immediate",
          matchType: "Ready-now requests",
          keywords: <String>["repair"],
        ),
        ProCircleConfig(
          id: "quotes",
          label: "Quotes",
          matchType: "Terms and prices",
          keywords: <String>["quote"],
        ),
      ];

  group("ProApexPolicy", () {
    test("toggleCircle switches only the selected circle", () {
      final rows = ProApexPolicy.toggleCircle(
        circles: circles(),
        circleId: "immediate",
      );

      expect(rows.first.isActive, isTrue);
      expect(rows.last.isActive, isFalse);

      final toggledBack = ProApexPolicy.toggleCircle(
        circles: rows,
        circleId: "immediate",
      );
      expect(toggledBack.first.isActive, isFalse);
    });

    test("active lead forces all circles off and blocks receiving matches", () {
      final activeRows = ProApexPolicy.toggleCircle(
        circles: circles(),
        circleId: "immediate",
      );
      final lockedRows = ProApexPolicy.toggleCircle(
        circles: activeRows,
        circleId: "quotes",
        hasActiveLead: true,
      );

      expect(lockedRows.any((circle) => circle.isActive), isFalse);
      expect(
        ProApexPolicy.canReceiveMatches(
          circles: lockedRows,
          hasActiveLead: true,
        ),
        isFalse,
      );
    });

    test("setKeywords trims, dedupes, and caps assigned keywords", () {
      final rows = ProApexPolicy.setKeywords(
        circles: circles(),
        circleId: "quotes",
        keywords: <String>[
          " quote ",
          "",
          "install",
          "quote",
          "same day",
          "pickup",
          "premium",
          "licensed",
          "delivery",
          "repair",
        ],
      );

      expect(rows.last.keywords, <String>[
        "quote",
        "install",
        "same day",
        "pickup",
        "premium",
        "licensed",
        "delivery",
        "repair",
      ]);
    });

    test("paused users cannot receive matches until pause expires", () {
      final clock = DateTime.utc(2026, 6, 14, 12);
      final activeRows = ProApexPolicy.toggleCircle(
        circles: circles(),
        circleId: "immediate",
      );

      expect(
        ProApexPolicy.canReceiveMatches(
          circles: activeRows,
          pausedUntil: clock.add(const Duration(minutes: 30)),
          now: clock,
        ),
        isFalse,
      );
      expect(
        ProApexPolicy.canReceiveMatches(
          circles: activeRows,
          pausedUntil: clock.subtract(const Duration(minutes: 1)),
          now: clock,
        ),
        isTrue,
      );
    });
  });
}
