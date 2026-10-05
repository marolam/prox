import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/party_referral_badge_service.dart';

const _verified = <String, dynamic>{
  'uid': 'me',
  'partyInPersonQrRequested': true,
  'inPersonVerified': true,
};

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'exact referral listeners decorate only supplied confirmed Party members',
    () async {
      final db = FakeFirebaseFirestore();
      final accounts = StreamController<String?>.broadcast();
      final paths = <String>[];
      await db.doc('users/verified/referrals/me').set(_verified);
      await db.doc('users/pending/referrals/me').set({
        ..._verified,
        'inPersonVerified': false,
      });
      await db.doc('users/plain/referrals/me').set({
        ..._verified,
        'partyInPersonQrRequested': false,
      });
      await db.doc('users/wrong/referrals/me').set({
        ..._verified,
        'uid': 'someone_else',
      });
      await db.doc('users/stranger/referrals/me').set(_verified);
      await db
          .doc('users/verified/business/forged/referrals/me')
          .set(_verified);
      final service = PartyReferralBadgeService(
        currentUid: () => 'me',
        accountChanges: () => accounts.stream,
        referralDocuments: (path) {
          paths.add(path);
          return db.doc(path).snapshots().map((snapshot) => snapshot.data());
        },
      );
      final seen = <Set<String>>[];
      final subscription = service
          .watchIncomingReferrerUids(
            expectedUid: 'me',
            confirmedPartyUids: [
              'verified',
              'pending',
              'plain',
              'wrong',
              'missing',
              'verified',
              '',
              'me',
              'invalid/path',
            ],
          )
          .listen(seen.add);
      await _flush();
      expect(seen.last, {'verified'});
      expect(paths.toSet(), {
        'users/verified/referrals/me',
        'users/pending/referrals/me',
        'users/plain/referrals/me',
        'users/wrong/referrals/me',
        'users/missing/referrals/me',
      });
      expect(
        paths.length,
        5,
        reason: 'Duplicate and invalid candidates never create extra reads.',
      );
      await db.doc('users/pending/referrals/me').update({
        'inPersonVerified': true,
      });
      await _flush();
      expect(seen.last, {'verified', 'pending'});
      await db.doc('users/verified/referrals/me').delete();
      await _flush();
      expect(seen.last, {
        'pending',
      }, reason: 'A removed referral loses its badge immediately.');
      await subscription.cancel();
      await accounts.close();
    },
  );

  test(
    'late old-account results and errors are suppressed before auth notification',
    () async {
      String? current = 'me';
      final accounts = StreamController<String?>.broadcast();
      final source = StreamController<Map<String, dynamic>?>.broadcast();
      final paths = <String>[];
      final service = PartyReferralBadgeService(
        currentUid: () => current,
        accountChanges: () => accounts.stream,
        referralDocuments: (path) {
          paths.add(path);
          return source.stream;
        },
      );
      final seen = <Set<String>>[];
      final errors = <Object>[];
      final subscription = service
          .watchIncomingReferrerUids(
            expectedUid: 'me',
            confirmedPartyUids: ['peer'],
          )
          .listen(seen.add, onError: errors.add);
      await _flush();
      current = 'new_account';
      source.add(_verified);
      source.addError(StateError('Old private referral failure'));
      await _flush();
      expect(seen.every((value) => value.isEmpty), isTrue);
      expect(errors, isEmpty);
      accounts.add(current);
      await _flush();
      expect(seen.last, isEmpty);
      expect(source.hasListener, isFalse);
      expect(paths, [
        'users/peer/referrals/me',
      ], reason: 'Old Party IDs never cause reads for the new account.');
      await subscription.cancel();
      await accounts.close();
      await source.close();
    },
  );

  test(
    'paused consumers cannot replay a private badge after account change',
    () async {
      String? current = 'me';
      final accounts = StreamController<String?>.broadcast();
      final source = StreamController<Map<String, dynamic>?>.broadcast();
      final service = PartyReferralBadgeService(
        currentUid: () => current,
        accountChanges: () => accounts.stream,
        referralDocuments: (_) => source.stream,
      );
      final seen = <Set<String>>[];
      final subscription = service
          .watchIncomingReferrerUids(
            expectedUid: 'me',
            confirmedPartyUids: ['peer'],
          )
          .listen(seen.add);
      await _flush();
      subscription.pause();
      source.add(_verified);
      await _flush();
      current = 'other';
      accounts.add(current);
      await _flush();
      subscription.resume();
      await _flush();
      expect(seen.every((value) => value.isEmpty), isTrue);
      expect(source.hasListener, isFalse);
      await subscription.cancel();
      await accounts.close();
      await source.close();
    },
  );

  test(
    'consumers cancel independently and can listen again after unmount',
    () async {
      final accounts = StreamController<String?>.broadcast();
      final source = StreamController<Map<String, dynamic>?>.broadcast();
      var listeners = 0;
      var cancellations = 0;
      final service = PartyReferralBadgeService(
        currentUid: () => 'me',
        accountChanges: () => accounts.stream,
        referralDocuments: (_) => Stream<Map<String, dynamic>?>.multi((output) {
          listeners++;
          final subscription = source.stream.listen(output.add);
          output.onCancel = () async {
            cancellations++;
            await subscription.cancel();
          };
        }),
      );
      final stream = service.watchIncomingReferrerUids(
        expectedUid: 'me',
        confirmedPartyUids: ['peer'],
      );
      final first = <Set<String>>[];
      final second = <Set<String>>[];
      final firstSubscription = stream.listen(first.add);
      final secondSubscription = stream.listen(second.add);
      await _flush();
      expect(listeners, 2);
      await firstSubscription.cancel();
      expect(cancellations, 1);
      source.add(_verified);
      await _flush();
      expect(first.every((value) => value.isEmpty), isTrue);
      expect(second.last, {'peer'});
      await secondSubscription.cancel();
      expect(cancellations, 2);
      expect(source.hasListener, isFalse);
      final third = <Set<String>>[];
      final thirdSubscription = stream.listen(third.add);
      await _flush();
      source.add(_verified);
      await _flush();
      expect(listeners, 3);
      expect(third.last, {'peer'});
      await thirdSubscription.cancel();
      expect(cancellations, 3);
      await accounts.close();
      await source.close();
    },
  );

  test(
    'a failed document listener removes its badge and reports the error',
    () async {
      final accounts = StreamController<String?>.broadcast();
      final source = StreamController<Map<String, dynamic>?>.broadcast();
      final service = PartyReferralBadgeService(
        currentUid: () => 'me',
        accountChanges: () => accounts.stream,
        referralDocuments: (_) => source.stream,
      );
      final seen = <Set<String>>[];
      final errors = <Object>[];
      final subscription = service
          .watchIncomingReferrerUids(
            expectedUid: 'me',
            confirmedPartyUids: ['peer'],
          )
          .listen(seen.add, onError: errors.add);
      await _flush();
      source.add(_verified);
      await _flush();
      expect(seen.last, {'peer'});
      source.addError(StateError('Permission revoked'));
      await _flush();
      expect(seen.last, isEmpty);
      expect(errors, hasLength(1));
      await subscription.cancel();
      await accounts.close();
      await source.close();
    },
  );

  test('stale account inputs never attach a document listener', () async {
    final accounts = StreamController<String?>.broadcast();
    var reads = 0;
    final service = PartyReferralBadgeService(
      currentUid: () => 'new_account',
      accountChanges: () => accounts.stream,
      referralDocuments: (_) {
        reads++;
        return const Stream.empty();
      },
    );
    final seen = <Set<String>>[];
    final subscription = service
        .watchIncomingReferrerUids(
          expectedUid: 'me',
          confirmedPartyUids: ['peer'],
        )
        .listen(seen.add);
    await _flush();
    expect(reads, 0);
    expect(seen.last, isEmpty);
    await subscription.cancel();
    await accounts.close();
  });
}
