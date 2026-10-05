import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prox/services/auth/authenticated_callable.dart';

class BackgroundAccountChanged implements Exception {}

/// Reads are bound to the account that opened the view, including delayed
/// callable responses and an auth-token change before the server receives it.
class BackgroundOpportunityService {
  BackgroundOpportunityService({
    required String? Function() currentUid,
    required Stream<String?> Function() accountChanges,
    required Future<Map<String, dynamic>> Function(
      String name,
      Map<String, dynamic> data,
    )
    invoke,
  }) : _currentUid = currentUid,
       _accountChanges = accountChanges,
       _invoke = invoke;

  static final instance = BackgroundOpportunityService(
    currentUid: () => FirebaseAuth.instance.currentUser?.uid,
    accountChanges: () =>
        FirebaseAuth.instance.authStateChanges().map((user) => user?.uid),
    invoke: (name, data) async {
      final response = await callAuthenticatedFunction<Map>(name, data);
      return Map<String, dynamic>.from(response.data);
    },
  );

  final String? Function() _currentUid;
  final Stream<String?> Function() _accountChanges;
  final Future<Map<String, dynamic>> Function(
    String name,
    Map<String, dynamic> data,
  )
  _invoke;

  String? get currentUid => _currentUid();
  Stream<String?> get accountChanges => _accountChanges();

  Future<Map<String, dynamic>> _read(
    String accountUid,
    String name,
    Map<String, dynamic> data,
  ) async {
    if (accountUid.isEmpty || currentUid != accountUid) {
      throw BackgroundAccountChanged();
    }
    final result = await _invoke(name, {...data, 'expectedUid': accountUid});
    if (currentUid != accountUid) throw BackgroundAccountChanged();
    return result;
  }

  Future<List<Map<String, dynamic>>> list(String accountUid) async {
    final result = await _read(accountUid, 'listBackgroundOpportunities', {});
    return (result['opportunities'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> get(String accountUid, String opportunityId) =>
      _read(accountUid, 'getBackgroundOpportunity', {
        'opportunityId': opportunityId,
      });
}
