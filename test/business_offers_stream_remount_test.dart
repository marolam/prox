import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/models/business_offer.dart';
import 'package:prox/screens/business/business_offers_screen.dart';
import 'package:prox/services/business_mode/business_offers_service.dart';
import 'package:prox/services/business_mode/business_storefront_service.dart';
import 'package:prox/utils/auth_bound_stream.dart';

class _LiveOffers implements BusinessOffersRepository {
  _LiveOffers({required this.admin});

  final bool admin;
  final accounts = StreamController<String?>.broadcast(sync: true);
  final owned = StreamController<List<BusinessOffer>>.broadcast(sync: true);
  final reviewQueue = StreamController<List<BusinessOffer>>.broadcast(
    sync: true,
  );

  @override
  String? get currentUid => 'alice';
  @override
  Stream<String?> watchUid() => accounts.stream;
  @override
  Future<bool> canCreate(String uid) async => false;
  @override
  Future<bool> isAdmin(String uid) async => admin;
  @override
  String newId() => throw UnsupportedError('This test reads existing offers.');
  @override
  Future<BusinessStorefrontDetails> defaults(String uid) async =>
      const BusinessStorefrontDetails();

  Stream<List<BusinessOffer>> _watch(
    String owner,
    StreamController<List<BusinessOffer>> source,
  ) => authBoundStream<List<BusinessOffer>>(
    accountChanges: watchUid(),
    currentUid: () => currentUid,
    watch: (uid) =>
        uid == owner ? source.stream : Stream.value(const <BusinessOffer>[]),
    empty: const <BusinessOffer>[],
  );

  @override
  Stream<List<BusinessOffer>> watchOwned(String uid) => _watch(uid, owned);
  @override
  Stream<List<BusinessOffer>> watchReviewQueue(String uid) =>
      _watch(uid, reviewQueue);
  @override
  Future<BusinessOfferPage> browse(String uid, {String? cursor}) async =>
      BusinessOfferPage([_offer('Public reviewed offer')], null);
  @override
  Future<void> save(
    String uid, {
    required String offerId,
    required String requestId,
    required int revision,
    required BusinessOfferDraft draft,
    required bool submit,
  }) => throw UnsupportedError('This test reads existing offers.');
  @override
  Future<void> change(
    String uid,
    BusinessOffer offer,
    String action,
    String requestId,
  ) => throw UnsupportedError('This test reads existing offers.');
  @override
  Future<void> review(
    String uid,
    BusinessOffer offer,
    String decision,
    String reason,
    String requestId,
  ) => throw UnsupportedError('This test reads existing offers.');

  Future<void> close() async {
    await Future.wait([accounts.close(), owned.close(), reviewQueue.close()]);
  }
}

BusinessOffer _offer(String title, {bool review = false}) => BusinessOffer(
  id: 'existing_offer',
  ownerUid: 'alice',
  title: title,
  description: 'A reviewed local bicycle service.',
  expiresAt: DateTime.now().add(const Duration(days: 7)),
  revision: 1,
  status: review ? 'pending_review' : 'draft',
);

void main() {
  for (final review in [false, true]) {
    final tab = review ? 'Review' : 'My offers';
    testWidgets(
      '$tab receives fresh private data after Browse disposes and remounts it',
      (tester) async {
        final repository = _LiveOffers(admin: review);
        addTearDown(repository.close);
        await tester.pumpWidget(
          MaterialApp(home: BusinessOffersScreen(repository: repository)),
        );
        await tester.pumpAndSettle();
        if (review) {
          await tester.tap(find.text(tab));
          await tester.pumpAndSettle();
        }

        final source = review ? repository.reviewQueue : repository.owned;
        expect(source.hasListener, isTrue);
        source.add([_offer('Private offer before Browse', review: review)]);
        await tester.pumpAndSettle();
        expect(find.text('Private offer before Browse'), findsOneWidget);

        await tester.tap(find.text('Browse'));
        await tester.pumpAndSettle();
        expect(source.hasListener, isFalse);
        expect(find.text('Private offer before Browse'), findsNothing);
        expect(find.text('Public reviewed offer'), findsOneWidget);
        source.add([_offer('Private offscreen update', review: review)]);
        await tester.pump();
        expect(find.text('Private offscreen update'), findsNothing);

        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(source.hasListener, isTrue);
        source.add([
          _offer('Fresh private offer after return', review: review),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Fresh private offer after return'), findsOneWidget);
        expect(find.text('Private offer before Browse'), findsNothing);
        expect(find.text('Private offscreen update'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(source.hasListener, isFalse);
      },
    );
  }
}
