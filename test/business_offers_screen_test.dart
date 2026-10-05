import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/models/business_offer.dart';
import 'package:prox/screens/business/business_offers_screen.dart';
import 'package:prox/services/business_mode/business_offers_service.dart';
import 'package:prox/services/business_mode/business_storefront_service.dart';

class _Offers implements BusinessOffersRepository {
  String? uid = 'alice';
  bool paid = false, admin = false;
  int ids = 0, failSaves = 0;
  final accounts = StreamController<String?>.broadcast();
  List<BusinessOffer> owned = [], queue = [];
  BusinessOfferPage page = const BusinessOfferPage([], null);
  Completer<BusinessOfferPage>? pendingBrowse;
  Completer<BusinessStorefrontDetails>? pendingDefaults;
  final saves = <Map<String, Object?>>[];
  final changes = <Map<String, String>>[];
  final reviews = <Map<String, String>>[];
  @override
  String? get currentUid => uid;
  @override
  Stream<String?> watchUid() => accounts.stream;
  @override
  String newId() => 'offer_test_${++ids}';
  @override
  Future<bool> canCreate(String uid) async => paid;
  @override
  Future<bool> isAdmin(String uid) async => admin;
  @override
  Future<BusinessStorefrontDetails> defaults(String uid) async =>
      pendingDefaults == null
      ? const BusinessStorefrontDetails()
      : await pendingDefaults!.future;
  @override
  Stream<List<BusinessOffer>> watchOwned(String uid) => Stream.value(owned);
  @override
  Stream<List<BusinessOffer>> watchReviewQueue(String uid) =>
      Stream.value(queue);
  @override
  Future<void> save(
    String uid, {
    required String offerId,
    required String requestId,
    required int revision,
    required BusinessOfferDraft draft,
    required bool submit,
  }) async {
    saves.add({
      'uid': uid,
      'offerId': offerId,
      'requestId': requestId,
      'revision': revision,
      'draft': draft,
      'submit': submit,
    });
    if (failSaves-- > 0) {
      throw FirebaseFunctionsException(
        code: 'unavailable',
        message: 'Connection interrupted. Retry the same draft.',
      );
    }
  }

  @override
  Future<void> change(
    String uid,
    BusinessOffer offer,
    String action,
    String requestId,
  ) async {
    changes.add({
      'uid': uid,
      'offerId': offer.id,
      'action': action,
      'requestId': requestId,
    });
  }

  @override
  Future<void> review(
    String uid,
    BusinessOffer offer,
    String decision,
    String reason,
    String requestId,
  ) async {
    reviews.add({
      'uid': uid,
      'offerId': offer.id,
      'decision': decision,
      'reason': reason,
      'requestId': requestId,
    });
  }

  @override
  Future<BusinessOfferPage> browse(String uid, {String? cursor}) async =>
      pendingBrowse == null ? page : await pendingBrowse!.future;
}

BusinessOffer _offer(String title, {String status = 'active'}) => BusinessOffer(
  id: 'offer_existing_1',
  ownerUid: 'alice',
  title: title,
  description: 'A clear local bicycle tune-up service.',
  terms: 'Parts quoted separately.',
  locationLabel: 'Westchester County',
  expiresAt: DateTime.now().add(const Duration(days: 7)),
  revision: 3,
  status: status,
);

Future<void> _show(
  WidgetTester tester,
  _Offers repository, {
  bool create = false,
  bool browse = false,
}) async {
  addTearDown(repository.accounts.close);
  await tester.pumpWidget(
    MaterialApp(
      home: BusinessOffersScreen(
        repository: repository,
        startCreating: create,
        initialBrowse: browse,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _editorButton(WidgetTester tester, String label) async {
  final button = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
  );
  final outer = find
      .descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(button, 250, scrollable: outer);
  // An inline error adds height above the retry button. Apply the final scroll
  // layout before testing its actual hit target, as a user waits for the frame.
  await tester.pumpAndSettle();
  expect(button.hitTestable(), findsOneWidget);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _fillDraft(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'Bike tune-up');
  await tester.enterText(
    find.byType(TextFormField).at(1),
    'A careful local bicycle tune-up service.',
  );
}

void main() {
  testWidgets(
    'an account change clears the open moderator note and disables its action',
    (tester) async {
      final repository = _Offers()
        ..admin = true
        ..queue = [
          _offer('Pending private moderation', status: 'pending_review'),
        ];
      await _show(tester, repository);
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Request changes'));
      await tester.tap(find.text('Request changes'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Private moderator draft');
      repository.uid = 'bob';
      repository.accounts.add('bob');
      await tester.pumpAndSettle();
      expect(find.text('Private moderator draft'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      final submit = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Send reason'),
      );
      expect(submit.onPressed, isNull);
      expect(repository.reviews, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Pending private moderation'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'personal accounts browse reviewed offers without paid management controls',
    (tester) async {
      final repository = _Offers()
        ..page = BusinessOfferPage([_offer('Reviewed tune-up')], null);
      await _show(tester, repository, browse: true);
      expect(find.text('Reviewed tune-up'), findsOneWidget);
      expect(find.text('Create offer'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Review'), findsNothing);
      expect(repository.saves, isEmpty);
      expect(repository.reviews, isEmpty);
    },
  );

  testWidgets('expired paid access still permits pausing an existing offer', (
    tester,
  ) async {
    final repository = _Offers()..owned = [_offer('Existing offer')];
    await _show(tester, repository);
    expect(find.text('Create offer'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(
      find.textContaining('You can still pause or delete'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Pause'));
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(repository.changes.single['action'], 'withdraw');
    expect(repository.changes.single['uid'], 'alice');
    expect(repository.saves, isEmpty);
  });

  testWidgets(
    'paid offer submission requests human review and never reports immediate publication',
    (tester) async {
      final repository = _Offers()..paid = true;
      await _show(tester, repository, create: true);
      await _fillDraft(tester);
      await _editorButton(tester, 'Submit for human review');
      expect(repository.saves.single['submit'], true);
      expect(repository.saves.single['uid'], 'alice');
      expect(
        (repository.saves.single['draft'] as BusinessOfferDraft).title,
        'Bike tune-up',
      );
      expect(repository.reviews, isEmpty);
      expect(
        find.text('Submitted for human review. Publication follows approval.'),
        findsOneWidget,
      );
      expect(find.text('Offer published.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'uncertain save retry retains the original offer and request IDs',
    (tester) async {
      final repository = _Offers()
        ..paid = true
        ..failSaves = 1;
      await _show(tester, repository, create: true);
      await _fillDraft(tester);
      await _editorButton(tester, 'Save private draft');
      expect(
        find.text('Connection interrupted. Retry the same draft.'),
        findsOneWidget,
      );
      await _editorButton(tester, 'Save private draft');
      expect(repository.saves, hasLength(2));
      expect(repository.saves[1]['offerId'], repository.saves[0]['offerId']);
      expect(
        repository.saves[1]['requestId'],
        repository.saves[0]['requestId'],
      );
      expect(
        (repository.saves[1]['draft'] as BusinessOfferDraft).toMap(),
        (repository.saves[0]['draft'] as BusinessOfferDraft).toMap(),
      );
      expect(repository.reviews, isEmpty);
    },
  );

  testWidgets(
    'account changes remove cached public offers and discard late browse responses',
    (tester) async {
      final repository = _Offers()
        ..page = BusinessOfferPage([_offer('Old account visible offer')], null);
      await _show(tester, repository, browse: true);
      expect(find.text('Old account visible offer'), findsOneWidget);
      repository.uid = 'bob';
      repository.accounts.add('bob');
      await tester.pumpAndSettle();
      expect(find.text('Old account visible offer'), findsNothing);
      expect(find.text('Your account changed. Reopen offers.'), findsOneWidget);

      final late = _Offers()..pendingBrowse = Completer<BusinessOfferPage>();
      addTearDown(late.accounts.close);
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessOffersScreen(
            key: const ValueKey('late-browse'),
            repository: late,
            initialBrowse: true,
          ),
        ),
      );
      await tester.pump();
      late.uid = 'bob';
      late.accounts.add('bob');
      await tester.pump();
      late.pendingBrowse!.complete(
        BusinessOfferPage([_offer('Delayed old account offer')], null),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delayed old account offer'), findsNothing);
      expect(find.text('Your account changed. Reopen offers.'), findsOneWidget);
    },
  );

  testWidgets(
    'account switch clears an editor draft and rejects late private defaults',
    (tester) async {
      final repository = _Offers()
        ..paid = true
        ..pendingDefaults = Completer<BusinessStorefrontDetails>();
      await _show(tester, repository, create: true);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Private owner draft',
      );
      repository.uid = 'bob';
      repository.accounts.add('bob');
      await tester.pump();
      repository.pendingDefaults!.complete(
        const BusinessStorefrontDetails(
          serviceAreaText: 'Private prior area',
          meetupTerms: 'Private prior terms',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Private owner draft'), findsNothing);
      expect(find.text('Private prior area'), findsNothing);
      expect(find.text('Your account changed. Reopen offers.'), findsOneWidget);
      expect(repository.saves, isEmpty);
    },
  );

  testWidgets(
    'admin cancellation preserves pending review; rejection routes the supplied reason safely',
    (tester) async {
      final repository = _Offers()
        ..admin = true
        ..queue = [_offer('Pending reviewed offer', status: 'pending_review')];
      await _show(tester, repository);
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.text('Awaiting human review'), findsOneWidget);
      await tester.ensureVisible(find.text('Request changes'));
      await tester.tap(find.text('Request changes'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Unsent moderator note');
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 25));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(repository.reviews, isEmpty);
      await tester.tap(find.text('Request changes'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Please remove contact details.',
      );
      await tester.tap(find.text('Send reason'));
      await tester.pump(const Duration(milliseconds: 25));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(repository.reviews.single['decision'], 'reject');
      expect(
        repository.reviews.single['reason'],
        'Please remove contact details.',
      );
      expect(repository.reviews.single['offerId'], 'offer_existing_1');
      expect(repository.reviews.single['uid'], 'alice');
    },
  );
}
