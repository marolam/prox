import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/models/business_lead_models.dart';
import 'package:prox/screens/pro/pro_insights_screen.dart';
import 'package:prox/screens/pro/pro_storefront_screen.dart';
import 'package:prox/services/business_mode/business_insights_service.dart';
import 'package:prox/services/business_mode/business_storefront_service.dart';

class _Storefront implements BusinessStorefrontRepository {
  String? uid = 'alice';
  final accounts = StreamController<String?>.broadcast();
  BusinessStorefrontDetails details = const BusinessStorefrontDetails(
    hoursText: 'Mon–Fri, 9am–5pm ET',
    serviceAreaText: 'Brooklyn',
    meetupTerms: 'Confirm price in chat.',
  );
  Completer<BusinessStorefrontDetails>? pending;
  String? savedUid;
  BusinessStorefrontDetails? saved;
  @override
  String? get currentUid => uid;
  @override
  Stream<String?> watchUid() => accounts.stream;
  @override
  Future<BusinessStorefrontDetails> load(String uid) async =>
      pending == null ? details : await pending!.future;
  @override
  Future<void> save(String uid, BusinessStorefrontDetails details) async {
    savedUid = uid;
    saved = details;
  }
}

class _Insights implements BusinessInsightsRepository {
  String? uid = 'alice';
  final accounts = StreamController<String?>.broadcast();
  final summaries = StreamController<BusinessInsightsSummary>.broadcast();
  @override
  String? get currentUid => uid;
  @override
  Stream<String?> watchUid() => accounts.stream;
  @override
  Stream<BusinessInsightsSummary> watch(String uid) => summaries.stream;
}

void main() {
  final created = DateTime.utc(2026, 10, 5, 12);
  BusinessLeadRecord lead(
    String id, {
    String status = 'new',
    DateTime? createdAt,
    DateTime? respondedAt,
    DateTime? wonAt,
    bool? qualified,
  }) => BusinessLeadRecord(
    leadId: id,
    score: 50,
    scoreBand: BusinessLeadScoreBand.warm,
    scoreVersion: 'bm_v1',
    scoredAt: created,
    updatedAt: created.add(const Duration(days: 1)),
    status: status,
    createdAt: createdAt,
    respondedAt: respondedAt,
    wonAt: wonAt,
    qualified: qualified,
  );

  test('empty insight coverage has no invented response or close time', () {
    final summary = BusinessInsightsSummary.fromLeads([]);
    expect(summary.responsePercent, isNull);
    expect(summary.medianClose, isNull);
    expect(summary.wonLeads, 0);
  });

  test(
    'insights use recorded outcomes and exclude missing or reversed timing',
    () {
      final summary = BusinessInsightsSummary.fromLeads([
        lead(
          'one',
          status: 'won',
          createdAt: created,
          respondedAt: created.add(const Duration(minutes: 2)),
          wonAt: created.add(const Duration(minutes: 10)),
          qualified: true,
        ),
        lead(
          'two',
          status: ' WON ',
          createdAt: created,
          wonAt: created.add(const Duration(minutes: 30)),
        ),
        lead('legacy', status: 'won', wonAt: created),
        lead(
          'invalid',
          status: 'won',
          createdAt: created,
          respondedAt: created.subtract(const Duration(minutes: 1)),
          wonAt: created.subtract(const Duration(minutes: 1)),
        ),
        lead(
          'responded',
          createdAt: created,
          respondedAt: created.add(const Duration(minutes: 5)),
        ),
      ]);
      expect(summary.responsePercent, 40);
      expect(summary.wonLeads, 4);
      expect(summary.qualifiedLeads, 1);
      expect(summary.timedWins, 2);
      expect(summary.medianClose, const Duration(minutes: 20));
    },
  );

  test('storefront details trim content and reject over-limit text', () {
    expect(
      const BusinessStorefrontDetails(
        hoursText: '  By appointment  ',
      ).validatedFields()['hoursText'],
      'By appointment',
    );
    expect(
      () => BusinessStorefrontDetails(
        serviceAreaText: 'a' * 501,
      ).validatedFields(),
      throwsArgumentError,
    );
  });

  testWidgets(
    'storefront loads and saves actual service details for opening UID',
    (tester) async {
      final store = _Storefront();
      addTearDown(store.accounts.close);
      await tester.pumpWidget(
        MaterialApp(home: ProStorefrontScreen(repository: store)),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      expect(
        tester.widget<TextField>(fields.at(0)).controller!.text,
        'Mon–Fri, 9am–5pm ET',
      );
      await tester.enterText(fields.at(0), 'Weekend appointments');
      await tester.enterText(fields.at(1), 'Queens');
      await tester.ensureVisible(find.text('Save service details'));
      await tester.tap(find.text('Save service details'));
      await tester.pumpAndSettle();
      expect(store.savedUid, 'alice');
      expect(store.saved!.hoursText, 'Weekend appointments');
      expect(store.saved!.serviceAreaText, 'Queens');
      expect(store.saved!.meetupTerms, 'Confirm price in chat.');
    },
  );

  testWidgets(
    'late storefront load cannot reveal prior account after switching',
    (tester) async {
      final store = _Storefront()
        ..pending = Completer<BusinessStorefrontDetails>();
      addTearDown(store.accounts.close);
      await tester.pumpWidget(
        MaterialApp(home: ProStorefrontScreen(repository: store)),
      );
      await tester.pump();
      store.uid = 'bob';
      store.accounts.add('bob');
      await tester.pump();
      store.pending!.complete(store.details);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(
        find.text('Sign in and reopen Storefront to continue.'),
        findsOneWidget,
      );
      expect(store.saved, isNull);
    },
  );

  testWidgets(
    'insights show real counts and clear cached data on account switch',
    (tester) async {
      final repository = _Insights();
      addTearDown(repository.accounts.close);
      addTearDown(repository.summaries.close);
      await tester.pumpWidget(
        MaterialApp(home: ProInsightsScreen(repository: repository)),
      );
      await tester.pump();
      final summary = BusinessInsightsSummary.fromLeads([
        lead('replied', respondedAt: created),
        lead('waiting'),
      ]);
      repository.summaries.add(summary);
      await tester.pumpAndSettle();
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('92%'), findsNothing);
      repository.uid = 'bob';
      repository.accounts.add('bob');
      await tester.pumpAndSettle();
      repository.summaries.add(summary);
      await tester.pumpAndSettle();
      expect(find.text('50%'), findsNothing);
      expect(
        find.text('Sign in and reopen Insights to continue.'),
        findsOneWidget,
      );
    },
  );
}
