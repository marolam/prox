import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/auth/authenticated_callable.dart';

void main() {
  test('stale token retries once with the original request', () async {
    var calls = 0;
    var refreshes = 0;
    final result = await retryAuthenticatedCall(
      () async {
        if (++calls == 1) {
          throw FirebaseFunctionsException(
            code: 'unauthenticated',
            message: 'Stale token',
          );
        }
        return 'receipt';
      },
      ownerUid: 'owner',
      currentUid: () => 'owner',
      refreshToken: () async => refreshes++,
    );
    expect(result, 'receipt');
    expect(calls, 2);
    expect(refreshes, 1);
  });

  test('account change during refresh prevents replay', () async {
    var uid = 'owner';
    var calls = 0;
    await expectLater(
      retryAuthenticatedCall(
        () async {
          calls++;
          throw FirebaseFunctionsException(
            code: 'unauthenticated',
            message: 'Stale token',
          );
        },
        ownerUid: 'owner',
        currentUid: () => uid,
        refreshToken: () async => uid = 'other',
      ),
      throwsStateError,
    );
    expect(calls, 1);
  });

  test('non-auth failures are preserved without retries', () async {
    var refreshes = 0;
    await expectLater(
      retryAuthenticatedCall(
        () async => throw FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'Access denied',
        ),
        ownerUid: 'owner',
        currentUid: () => 'owner',
        refreshToken: () async => refreshes++,
      ),
      throwsA(isA<FirebaseFunctionsException>()),
    );
    expect(refreshes, 0);
  });

  test('persistent authentication failure only retries once', () async {
    var calls = 0;
    await expectLater(
      retryAuthenticatedCall(
        () async {
          calls++;
          throw FirebaseFunctionsException(
            code: 'unauthenticated',
            message: 'Stale token',
          );
        },
        ownerUid: 'owner',
        currentUid: () => 'owner',
        refreshToken: () async {},
      ),
      throwsA(isA<FirebaseFunctionsException>()),
    );
    expect(calls, 2);
  });
}
