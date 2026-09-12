import "package:flutter_test/flutter_test.dart";
import "package:prox/models/business_lead_models.dart";

void main() {
  BusinessLeadRecord lead({
    required String id,
    required int score,
    required BusinessLeadScoreBand band,
    String status = "new",
    DateTime? slaDueAt,
    DateTime? wonAt,
  }) {
    final now = DateTime.utc(2026, 6, 14, 12);
    return BusinessLeadRecord(
      leadId: id,
      score: score,
      scoreBand: band,
      scoreVersion: BusinessLeadScoringServiceVersion.current,
      scoredAt: now,
      updatedAt: now,
      slaDueAt: slaDueAt,
      status: status,
      wonAt: wonAt,
    );
  }

  group("BusinessLeadInboxPolicy", () {
    test("open filter hides closed leads and prioritizes overdue SLA", () {
      final clock = DateTime.utc(2026, 6, 14, 12);
      final rows = BusinessLeadInboxPolicy.apply(
        leads: <BusinessLeadRecord>[
          lead(
            id: "hot-later",
            score: 92,
            band: BusinessLeadScoreBand.hot,
            slaDueAt: clock.add(const Duration(hours: 2)),
          ),
          lead(
            id: "warm-overdue",
            score: 55,
            band: BusinessLeadScoreBand.warm,
            slaDueAt: clock.subtract(const Duration(minutes: 5)),
          ),
          lead(
            id: "won-hidden",
            score: 100,
            band: BusinessLeadScoreBand.hot,
            status: "won",
          ),
        ],
        filter: BusinessLeadInboxFilter.open,
        now: clock,
      );

      expect(rows.map((lead) => lead.leadId), <String>[
        "warm-overdue",
        "hot-later",
      ]);
    });

    test("hot and overdue filters only include active matching leads", () {
      final clock = DateTime.utc(2026, 6, 14, 12);
      final leads = <BusinessLeadRecord>[
        lead(
          id: "hot-open",
          score: 80,
          band: BusinessLeadScoreBand.hot,
          slaDueAt: clock.add(const Duration(minutes: 30)),
        ),
        lead(
          id: "hot-won",
          score: 90,
          band: BusinessLeadScoreBand.hot,
          status: "won",
          slaDueAt: clock.subtract(const Duration(minutes: 30)),
        ),
        lead(
          id: "warm-overdue",
          score: 50,
          band: BusinessLeadScoreBand.warm,
          slaDueAt: clock.subtract(const Duration(minutes: 15)),
        ),
      ];

      final hotRows = BusinessLeadInboxPolicy.apply(
        leads: leads,
        filter: BusinessLeadInboxFilter.hot,
        now: clock,
      );
      final overdueRows = BusinessLeadInboxPolicy.apply(
        leads: leads,
        filter: BusinessLeadInboxFilter.overdue,
        now: clock,
      );

      expect(hotRows.map((lead) => lead.leadId), <String>["hot-open"]);
      expect(overdueRows.map((lead) => lead.leadId), <String>["warm-overdue"]);
    });

    test("won filter sorts by most recent win", () {
      final clock = DateTime.utc(2026, 6, 14, 12);
      final rows = BusinessLeadInboxPolicy.apply(
        leads: <BusinessLeadRecord>[
          lead(
            id: "older-win",
            score: 100,
            band: BusinessLeadScoreBand.hot,
            status: "won",
            wonAt: clock.subtract(const Duration(days: 2)),
          ),
          lead(
            id: "newer-win",
            score: 50,
            band: BusinessLeadScoreBand.warm,
            status: "won",
            wonAt: clock.subtract(const Duration(hours: 1)),
          ),
        ],
        filter: BusinessLeadInboxFilter.won,
        now: clock,
      );

      expect(rows.map((lead) => lead.leadId), <String>[
        "newer-win",
        "older-win",
      ]);
    });
  });
}

class BusinessLeadScoringServiceVersion {
  static const String current = "bm_v1";
}
