import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Recovers one stale token without replaying a request under another account.
Future<T> retryAuthenticatedCall<T>(
  Future<T> Function() invoke, {
  required String ownerUid,
  required String? Function() currentUid,
  required Future<void> Function() refreshToken,
}) async {
  void checkAccount() {
    if (ownerUid.isEmpty || currentUid() != ownerUid) {
      throw StateError('Your account changed. Reopen this screen.');
    }
  }

  checkAccount();
  try {
    final result = await invoke();
    checkAccount();
    return result;
  } on FirebaseFunctionsException catch (error) {
    if (error.code != 'unauthenticated') rethrow;
    checkAccount();
    await refreshToken();
    checkAccount();
    final result = await invoke();
    checkAccount();
    return result;
  }
}

Future<HttpsCallableResult<T>> callAuthenticatedFunction<T>(
  String name,
  Map<String, dynamic> data, {
  Duration timeout = const Duration(seconds: 20),
}) {
  final auth = FirebaseAuth.instance;
  final uid = auth.currentUser?.uid;
  if (uid == null ||
      (data['expectedUid'] != null && data['expectedUid'] != uid)) {
    throw StateError('Sign in to the account that opened this screen.');
  }
  final callable = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  ).httpsCallable(name, options: HttpsCallableOptions(timeout: timeout));
  final payload = {...data, 'expectedUid': uid};
  return retryAuthenticatedCall(
    () => callable.call<T>(payload),
    ownerUid: uid,
    currentUid: () => auth.currentUser?.uid,
    refreshToken: () async {
      await auth.currentUser!.getIdToken(true);
    },
  );
}
