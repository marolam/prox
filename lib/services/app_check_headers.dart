import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

Future<Map<String, String>> appCheckHeaders() async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS))
    return const {};
  final token = await FirebaseAppCheck.instance.getToken();
  if (token == null || token.isEmpty) {
    throw StateError(
      'App verification is unavailable. Reopen Prox and try again.',
    );
  }
  return {'X-Firebase-AppCheck': token};
}
