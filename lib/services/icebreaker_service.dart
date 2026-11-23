import 'dart:async';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:prox/services/matching/matching_mode_service.dart';
import 'package:prox/services/presence_writer.dart';
import 'package:prox/services/runtime_diagnostics_service.dart';

class IcebreakerSignal {
  const IcebreakerSignal({
    required this.key,
    required this.colorIndex,
    required this.symbolIndex,
    required this.mark,
    required this.band,
  });
  final String key;
  final int colorIndex;
  final int symbolIndex;
  final String mark;
  final String band;

  factory IcebreakerSignal.fromMap(Map<String, dynamic> data) {
    final color = data['colorIndex'];
    final symbol = data['symbolIndex'];
    if (data['key'] is! String ||
        data['mark'] is! String ||
        color is! int ||
        color < 0 ||
        color > 7 ||
        symbol is! int ||
        symbol < 0 ||
        symbol > 7 ||
        !const ['around', 'near', 'close'].contains(data['band'])) {
      throw const FormatException('Invalid Icebreaker signal.');
    }
    return IcebreakerSignal(
      key: data['key'] as String,
      colorIndex: color,
      symbolIndex: symbol,
      mark: data['mark'] as String,
      band: data['band'] as String,
    );
  }
}

class IcebreakerEncounter {
  const IcebreakerEncounter({
    required this.myReveal,
    required this.revealed,
    required this.myAdd,
    required this.connected,
    required this.keywords,
    required this.peerName,
  });
  final bool myReveal;
  final bool revealed;
  final bool myAdd;
  final bool connected;
  final List<String> keywords;
  final String? peerName;

  factory IcebreakerEncounter.fromMap(Map<String, dynamic> data) {
    if (data['myReveal'] is! bool ||
        data['revealed'] is! bool ||
        data['myAdd'] is! bool ||
        data['connected'] is! bool ||
        (data['revealed'] == true &&
            (data['keywords'] is! List || data['peerName'] is! String))) {
      throw const FormatException('Invalid Icebreaker encounter.');
    }
    final revealed = data['revealed'] as bool;
    final keywords = revealed
        ? List<String>.from(data['keywords'] as List)
        : <String>[];
    return IcebreakerEncounter(
      myReveal: data['myReveal'] as bool,
      revealed: revealed,
      myAdd: data['myAdd'] as bool,
      connected: data['connected'] as bool,
      keywords: List.unmodifiable(keywords),
      peerName: revealed ? data['peerName'] as String : null,
    );
  }
}

typedef IcebreakerCall = Future<Map<String, dynamic>> Function(
  String uid,
  Map<String, Object?> data,
);

class IcebreakerService extends ChangeNotifier {
  IcebreakerService({
    IcebreakerCall? call,
    Future<void> Function()? refreshLocation,
    DateTime Function()? now,
  }) : _call = call ?? _firebaseCall,
       _refreshLocation = refreshLocation ?? _refreshPresence,
       _now = now ?? DateTime.now;

  final IcebreakerCall _call;
  final Future<void> Function() _refreshLocation;
  final DateTime Function() _now;
  String? _uid;
  String? _token;
  int _revision = 0;
  bool _disposed = false;
  bool busy = false;
  bool nearby = false;
  bool hasEncounter = false;
  String band = 'none';
  String? code;
  String? error;
  List<IcebreakerSignal> signals = const [];
  IcebreakerEncounter? encounter;
  DateTime? _validUntil;

  static Future<Map<String, dynamic>> _firebaseCall(
    String uid,
    Map<String, Object?> data,
  ) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Your signed-in account changed.',
      );
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable(
          'icebreaker',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 12)),
        )
        .call<Map<String, dynamic>>({...data, 'expectedUid': uid});
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Your signed-in account changed.',
      );
    }
    return result.data;
  }

  static Future<void> _refreshPresence() async {
    await MatchingModeService.instance.flushPendingSync();
    final wrote = await PresenceWriter.instance.writeOneShot(
      reason: 'icebreaker_nearby',
      accuracy: LocationAccuracy.high,
    );
    if (!wrote) {
      throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Icebreaker needs a fresh location. Check location permissions and try outdoors.',
      );
    }
  }

  bool get active => _uid != null && _token != null && !_disposed;
  bool get live =>
      active && _validUntil != null && _validUntil!.isAfter(_now());

  Future<void> start(String uid) async {
    if (_disposed || _uid == uid && active) return;
    final revision = _revision + 1;
    await stop();
    if (_disposed || _revision != revision) return;
    _uid = uid;
    final random = Random.secure();
    _token = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    error = null;
    await refresh();
  }

  void expire() {
    if (_validUntil != null && !_validUntil!.isAfter(_now())) {
      _clearVisible();
      _notify();
    }
  }

  Future<void> refresh() => _request('observe');
  Future<void> join(String otherCode) => _request('join', code: otherCode);
  Future<void> reveal() => _request('reveal');
  Future<void> addToParty() => _request('add');
  Future<void> cancelEncounter() => _request('cancel');

  Future<void> _request(String action, {String? code}) async {
    if (!active || busy) return;
    final uid = _uid!, token = _token!, revision = _revision;
    busy = true;
    _notify();
    try {
      if (action == 'observe') await _refreshLocation();
      if (!_current(revision)) return;
      final result = await _call(uid, {
        'action': action,
        'token': token,
        if (code != null) 'code': code,
      });
      if (!_current(revision)) return;
      if (action == 'observe') {
        if (result['nearby'] is! bool ||
            result['signals'] is! List ||
            result['code'] is! String ||
            result['validUntilMs'] is! num ||
            !const [
              'none',
              'around',
              'near',
              'close',
            ].contains(result['band'])) {
          throw const FormatException('Invalid Icebreaker response.');
        }
        final validUntil = DateTime.fromMillisecondsSinceEpoch(
          (result['validUntilMs'] as num).toInt(),
        );
        if (!validUntil.isAfter(_now()))
          throw const FormatException(
            'The Icebreaker signal expired. Try again.',
          );
        final parsed = (result['signals'] as List)
            .map(
              (item) => IcebreakerSignal.fromMap(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false);
        nearby = result['nearby'] as bool;
        band = result['band'] as String;
        signals = parsed;
        this.code = result['code'] as String;
        _validUntil = validUntil;
      }
      encounter = result['encounter'] == null
          ? null
          : IcebreakerEncounter.fromMap(
              Map<String, dynamic>.from(result['encounter'] as Map),
            );
      hasEncounter = encounter != null;
      error = null;
    } catch (exception, stack) {
      if (!_current(revision)) return;
      _clearVisible();
      error = exception is FirebaseFunctionsException
          ? exception.code == 'not-found'
                ? 'Icebreaker is not enabled on the server yet. This pilot needs its backend deployed.'
                : exception.message ??
                      'Icebreaker could not refresh. Try again.'
          : 'Icebreaker could not refresh. Check your connection and try again.';
      RuntimeDiagnosticsService.instance.record(
        exception,
        stack,
        operation: 'Icebreaker $action',
      );
    } finally {
      if (_current(revision)) {
        busy = false;
        _notify();
      }
    }
  }

  bool _current(int revision) => !_disposed && active && revision == _revision;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _clearVisible() {
    nearby = false;
    band = 'none';
    signals = const [];
    code = null;
    encounter = null;
    hasEncounter = false;
    _validUntil = null;
  }

  Future<void> stop() async {
    final uid = _uid, token = _token;
    _revision++;
    _uid = null;
    _token = null;
    busy = false;
    hasEncounter = false;
    _clearVisible();
    _notify();
    if (uid == null || token == null) return;
    try {
      await _call(uid, {'action': 'stop', 'token': token});
    } catch (exception, stack) {
      RuntimeDiagnosticsService.instance.record(
        exception,
        stack,
        operation: 'Close Icebreaker session',
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
