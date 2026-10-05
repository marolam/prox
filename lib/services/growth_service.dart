import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prox/services/app_build_info_service.dart';
import 'package:prox/services/runtime_diagnostics_service.dart';
import 'package:prox/services/auth/authenticated_callable.dart';

typedef GrowthCaller =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, dynamic> data,
    );

Map<String, dynamic> growthMap(dynamic value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, dynamic>{};

class GrowthStatus {
  const GrowthStatus(this.data);
  final Map<String, dynamic> data;
  Map<String, dynamic> get config => growthMap(data['config']);
  Map<String, dynamic> get tester => growthMap(data['tester']);
  Map<String, dynamic> get progress => growthMap(data['progress']);
  Map<String, dynamic> get referral => growthMap(data['referral']);
  bool get enabled => config['enabled'] == true;
  bool get referralsEnabled =>
      enabled &&
      (config['stage'] == 'referrals' || config['stage'] == 'support');
  bool get enrolled => tester['joinedAtMs'] is num;
  int configInt(String field, int fallback) =>
      (config[field] as num?)?.toInt() ?? fallback;
}

/// Server-backed pilot operations. Failure here never blocks the Big 5.
class GrowthService extends ChangeNotifier with WidgetsBindingObserver {
  GrowthService._({GrowthCaller? caller, this.observeRuntime = true})
    : _caller = caller ?? _callFirebase;
  factory GrowthService.forTesting({required GrowthCaller caller}) =>
      GrowthService._(caller: caller, observeRuntime: false);
  static final instance = GrowthService._();
  final GrowthCaller _caller;
  final bool observeRuntime;
  String? _uid;
  String? _sessionId;
  DateTime? _sessionStarted;
  GrowthStatus? _status;
  GrowthStatus? get status => _status;
  String? get uid => _uid;
  bool _observing = false;
  bool _flushing = false;
  bool _applyingReferral = false;
  Timer? _retry;
  RuntimeIssue? _lastIssue;
  Future<void> _queueWrites = Future<void>.value();
  Future<String>? _installationFuture;
  int _generation = 0;
  final Set<String> _deletedOwners = {};
  String? lastError;

  static Future<Map<String, dynamic>> _callFirebase(
    String name,
    Map<String, dynamic> data,
  ) async {
    final result = await callAuthenticatedFunction<Map<String, dynamic>>(
      name,
      data,
    );
    return growthMap(result.data);
  }

  static String newRequestId() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<Map<String, dynamic>> call(
    String name, [
    Map<String, dynamic> data = const {},
  ]) async {
    final owner = _uid;
    final generation = _generation;
    if (owner == null || _deletedOwners.contains(owner))
      throw StateError('Sign in to continue.');
    if (data.containsKey('expectedUid') && data['expectedUid'] != owner) {
      throw StateError('Account changed. Try again.');
    }
    final result = await _caller(name, {...data, 'expectedUid': owner});
    if (generation != _generation || owner != _uid) {
      throw StateError('Account changed. Try again.');
    }
    return result;
  }

  Future<void> bindAccount(String? uid) async {
    if (_uid == uid) return;
    _generation++;
    _retry?.cancel();
    _uid = uid;
    _status = null;
    lastError = null;
    _sessionId = null;
    _sessionStarted = null;
    if (observeRuntime && !_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
      RuntimeDiagnosticsService.instance.addListener(_onDiagnostic);
    }
    notifyListeners();
    if (uid == null) return;
    if (observeRuntime) {
      _retry = Timer.periodic(const Duration(minutes: 2), (_) {
        unawaited(_flush());
      });
    }
    if (observeRuntime) {
      try {
        await _startSession();
      } catch (_) {
        /* Optional reporting. */
      }
    }
    await refresh();
    await _applyPendingReferral();
  }

  Future<void> refresh({bool sync = false}) async {
    if (_uid == null) return;
    final generation = _generation;
    try {
      final data = await call(sync ? 'syncGrowthProgress' : 'getGrowthStatus');
      _status = GrowthStatus(data);
      lastError = null;
    } catch (error) {
      if (generation != _generation) return;
      lastError = error is FirebaseFunctionsException
          ? error.message ?? 'Tester services are temporarily unavailable.'
          : 'Tester services are temporarily unavailable. Please try again.';
    }
    notifyListeners();
    if (observeRuntime) await _applyPendingReferral();
  }

  Future<void> join() async {
    await call('joinTesterCohort');
    await refresh(sync: true);
  }

  Future<Map<String, dynamic>> createInvite(String requestId) async {
    final owner = _uid;
    final deviceId = await _installationId();
    return call('createGrowthInvite', {
      'requestId': requestId,
      'deviceId': deviceId,
      'expectedUid': owner,
    });
  }

  Future<String> _installationId() =>
      _installationFuture ??= _loadInstallationId();

  Future<String> _loadInstallationId() async {
    final preferences = await SharedPreferences.getInstance();
    var deviceId = preferences.getString('growth.installation.v1');
    if (deviceId == null) {
      deviceId = newRequestId();
      await preferences.setString('growth.installation.v1', deviceId);
    }
    return deviceId;
  }

  Future<void> acceptReferral(String code, String requestId) async {
    final owner = _uid;
    final deviceId = await _installationId();
    await call('acceptGrowthReferral', {
      'code': code.trim().toUpperCase(),
      'deviceId': deviceId,
      'requestId': requestId,
      'expectedUid': owner,
    });
    await refresh(sync: true);
  }

  static String? referralCodeFromUri(Uri uri) {
    if (uri.userInfo.isNotEmpty || uri.hasPort) return null;
    final trustedWeb =
        uri.scheme == 'https' &&
        const {
          'prox-us.com',
          'www.prox-us.com',
        }.contains(uri.host.toLowerCase()) &&
        const ['/', '/referral.html', ''].contains(uri.path);
    final trustedApp = uri.scheme == 'prox' && uri.host == 'referral';
    if (!trustedWeb && !trustedApp) {
      return null;
    }
    final legacyCode = uri.queryParameters['code']?.trim().toUpperCase();
    final code =
        uri.queryParameters['growth']?.trim().toUpperCase() ??
        (legacyCode?.startsWith('PROX-P-') == true ? legacyCode : null);
    return code != null && RegExp(r'^PROX-P-[A-F0-9]{12}$').hasMatch(code)
        ? code
        : null;
  }

  Future<void> captureReferral(Uri uri) async {
    final code = referralCodeFromUri(uri);
    if (code == null) return;
    final preferences = await SharedPreferences.getInstance();
    if (!preferences.containsKey('growth.pendingReferral.v1')) {
      await preferences.setString('growth.pendingReferral.v1', code);
      await preferences.setString(
        'growth.pendingReferralRequest.v1',
        newRequestId(),
      );
    }
    await _applyPendingReferral();
  }

  Future<void> _applyPendingReferral() async {
    if (_applyingReferral || _uid == null || _status?.referralsEnabled != true)
      return;
    _applyingReferral = true;
    final generation = _generation;
    try {
      final preferences = await SharedPreferences.getInstance();
      final code = preferences.getString('growth.pendingReferral.v1');
      if (code == null) return;
      try {
        await acceptReferral(
          code,
          preferences.getString('growth.pendingReferralRequest.v1') ??
              newRequestId(),
        );
        if (generation == _generation) {
          await preferences.remove('growth.pendingReferral.v1');
          await preferences.remove('growth.pendingReferralRequest.v1');
        }
      } on FirebaseFunctionsException catch (error) {
        if (generation == _generation &&
            (const [
                  'invalid-argument',
                  'not-found',
                  'already-exists',
                ].contains(error.code) ||
                (error.code == 'failed-precondition' &&
                    (error.message?.contains('expired or was used') == true ||
                        error.message?.contains('first seven days') ==
                            true)))) {
          await preferences.remove('growth.pendingReferral.v1');
          await preferences.remove('growth.pendingReferralRequest.v1');
        }
      } catch (_) {
        // Keep attribution across login/offline retries; manual entry remains available.
      }
    } finally {
      _applyingReferral = false;
    }
  }

  Future<Map<String, dynamic>> _metadata() async {
    final full = await AppBuildInfoService.instance.fullVersion();
    return {
      'version': full.split('+').first,
      'build': full.contains('+') ? full.split('+').last : 'unknown',
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
    };
  }

  Future<void> _startSession() async {
    if (_uid == null) return;
    if (_sessionId != null) {
      final age = DateTime.now().difference(_sessionStarted!);
      if (age < const Duration(minutes: 30)) return;
      await _recordSession('end');
    }
    _sessionId = newRequestId();
    _sessionStarted = DateTime.now();
    await _recordSession('start');
  }

  Future<void> _recordSession(
    String event, {
    String? source,
    bool fatal = false,
  }) async {
    try {
      await _enqueueSession(event, source: source, fatal: fatal);
    } catch (_) {
      // Optional instrumentation cannot interrupt core actions or report itself.
    }
  }

  Future<void> _enqueueSession(
    String event, {
    String? source,
    bool fatal = false,
  }) async {
    final owner = _uid;
    final session = _sessionId;
    if (owner == null || session == null || _deletedOwners.contains(owner))
      return;
    final preferences = await SharedPreferences.getInstance();
    final metadata = await _metadata();
    if (owner != _uid || _deletedOwners.contains(owner)) return;
    final key = 'growth.pendingSessions.v1.$owner';
    final item = {
      'requestId': newRequestId(),
      'sessionId': session,
      'event': event,
      'diagnosticsConsent': RuntimeDiagnosticsService.instance.sharingEnabled,
      'metadata': metadata,
      if (source != null) 'source': source,
      'fatal': fatal,
    };
    await _mutateQueue(preferences, key, (queue) {
      if (_deletedOwners.contains(owner)) return;
      queue.add(item);
      // Bound local diagnostics storage during a long outage.
      trimSessionQueue(queue);
    });
    unawaited(_flush());
  }

  static List<Map<String, dynamic>> _decodeQueue(String? value) {
    if (value == null) return [];
    try {
      final data = jsonDecode(value);
      return data is List ? data.map(growthMap).toList() : [];
    } catch (_) {
      return [];
    }
  }

  static void trimSessionQueue(List<Map<String, dynamic>> queue) {
    while (queue.length > 100) {
      final oldestSession = queue.first['sessionId'];
      queue.removeWhere((item) => item['sessionId'] == oldestSession);
    }
  }

  Future<void> _mutateQueue(
    SharedPreferences preferences,
    String key,
    void Function(List<Map<String, dynamic>>) update,
  ) {
    final operation = _queueWrites.then((_) async {
      final queue = _decodeQueue(preferences.getString(key));
      update(queue);
      await preferences.setString(key, jsonEncode(queue));
    });
    _queueWrites = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> flushPendingSessions() => _flush();

  Future<void> _flush() async {
    if (_flushing || _uid == null) return;
    _flushing = true;
    final owner = _uid;
    try {
      final preferences = await SharedPreferences.getInstance();
      final key = 'growth.pendingSessions.v1.$owner';
      while (owner == _uid) {
        final queue = _decodeQueue(preferences.getString(key));
        if (queue.isEmpty) break;
        final item = queue.first;
        // Revoking crash consent also discards queued remote error reports.
        if (item['event'] != 'error' ||
            RuntimeDiagnosticsService.instance.sharingEnabled) {
          try {
            await call('recordGrowthSession', item);
          } on FirebaseFunctionsException catch (error) {
            if (!const [
              'failed-precondition',
              'invalid-argument',
              'not-found',
              'permission-denied',
            ].contains(error.code))
              rethrow;
            // An expired/orphan outcome must not block subsequent valid sessions.
          }
        }
        if (owner != _uid) break;
        await _mutateQueue(
          preferences,
          key,
          (queue) => queue.removeWhere(
            (entry) => entry['requestId'] == item['requestId'],
          ),
        );
      }
    } catch (_) {
      // Retry a bounded account-scoped queue without disrupting app startup.
    } finally {
      _flushing = false;
    }
  }

  void _onDiagnostic() {
    final issues = RuntimeDiagnosticsService.instance.issues;
    if (issues.isEmpty || identical(_lastIssue, issues.first)) return;
    _lastIssue = issues.first;
    if (!RuntimeDiagnosticsService.instance.sharingEnabled) return;
    final operation = issues.first.operation.toLowerCase();
    final source =
        const [
          'matching',
          'chat',
          'location',
          'network',
          'framework',
          'startup',
        ].where(operation.contains).firstOrNull ??
        'other';
    unawaited(
      _recordSession('error', source: source, fatal: issues.first.fatal),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_startSession());
      unawaited(refresh());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_recordSession('end'));
      _sessionId = null;
      _sessionStarted = null;
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      RuntimeDiagnosticsService.instance.removeListener(_onDiagnostic);
    }
    super.dispose();
  }

  Future<void> clearForUser(String uid) async {
    _deletedOwners.add(uid);
    if (_uid == uid) await bindAccount(null);
    await _queueWrites;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('growth.pendingSessions.v1.$uid');
  }
}
