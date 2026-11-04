import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prox/services/runtime_diagnostics_service.dart';

/// Local learning progress, scoped to an account; never grants product access.
class FirstUseService extends ChangeNotifier {
  FirstUseService(this.uid);

  static final Map<String, FirstUseService> _accounts = {};
  static FirstUseService forUser(String uid) =>
      _accounts.putIfAbsent(uid, () => FirstUseService(uid));

  final String uid;
  String get storageKey => 'first_use.v1.$uid';
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();
  Map<String, dynamic> _data = {};
  bool ready = false;
  bool touring = false;

  bool get enabled => _data['enabled'] == true;
  bool get welcomeSeen => _data['welcomeSeen'] == true;
  bool get hidden => _data['hidden'] == true;
  bool get finished => _data['finished'] == true;
  int get step => (_data['step'] as int?) ?? 0;
  Set<String> get completed =>
      Set<String>.from(_data['completed'] as List? ?? const []);
  Set<String> get tipsSeen =>
      Set<String>.from(_data['tipsSeen'] as List? ?? const []);

  Future<void> load({bool autoWelcome = false}) {
    if (ready) return Future<void>.value();
    return _loading ??= _read(autoWelcome).whenComplete(() => _loading = null);
  }

  Future<void> _read(bool autoWelcome) async {
    try {
      if (uid.isEmpty) throw StateError('Sign in before starting the guide.');
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(storageKey);
      if (raw != null) {
        final value = jsonDecode(raw);
        if (value is! Map<String, dynamic> ||
            value['enabled'] is! bool ||
            value['welcomeSeen'] is! bool ||
            value['hidden'] is! bool ||
            value['finished'] is! bool ||
            value['step'] is! int ||
            (value['step'] as int) < 0 ||
            (value['step'] as int) > 5 ||
            value['completed'] is! List ||
            (value['completed'] as List).any((item) => item is! String) ||
            value['tipsSeen'] is! List ||
            (value['tipsSeen'] as List).any((item) => item is! String)) {
          throw const FormatException('Invalid first-use progress');
        }
        _data = value;
      } else {
        _data = {
          'enabled': autoWelcome,
          'welcomeSeen': !autoWelcome,
          'hidden': false,
          'finished': false,
          'step': 0,
          'completed': <String>[],
          'tipsSeen': <String>[],
        };
        await _persist(preferences, _data);
      }
      ready = true;
    } catch (error, stack) {
      RuntimeDiagnosticsService.instance.record(
        error,
        stack,
        operation: 'Load first-use guidance',
      );
      rethrow;
    }
  }

  Future<void> _persist(
    SharedPreferences preferences,
    Map<String, dynamic> data,
  ) async {
    try {
      if (!await preferences.setString(storageKey, jsonEncode(data))) {
        throw StateError('Could not save first-use progress.');
      }
    } catch (error, stack) {
      // SharedPreferences caches writes before the platform acknowledges them.
      await preferences.reload();
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> _update(void Function(Map<String, dynamic>) change) {
    final write = _writes.then((_) async {
      await load();
      final next = Map<String, dynamic>.from(_data);
      change(next);
      final preferences = await SharedPreferences.getInstance();
      await _persist(preferences, next);
      _data = next;
      notifyListeners();
    });
    _writes = write.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        RuntimeDiagnosticsService.instance.record(
          error,
          stack,
          operation: 'Save first-use guidance',
        );
      },
    );
    return write;
  }

  Future<void> welcome({required bool startTour}) async {
    await _update((data) {
      data['enabled'] = true;
      data['welcomeSeen'] = true;
    });
    touring = startTour;
    notifyListeners();
  }

  Future<void> startTour({bool restart = false}) async {
    await _update((data) {
      data['enabled'] = true;
      data['welcomeSeen'] = true;
      data['hidden'] = false;
      data['finished'] = false;
      if (restart) {
        data['step'] = 0;
        data['tipsSeen'] = <String>[];
      }
    });
    touring = true;
    notifyListeners();
  }

  Future<void> moveTo(int value) => _update((data) {
    if (value < 0 || value > 5) throw RangeError.range(value, 0, 5);
    data['step'] = value;
  });

  Future<void> finishTour() async {
    await _update((data) => data['finished'] = true);
    touring = false;
    notifyListeners();
  }

  void pauseTour() {
    touring = false;
    notifyListeners();
  }

  Future<void> setHidden(bool value) =>
      _update((data) => data['hidden'] = value);

  Future<void> markComplete(Iterable<String> ids) => _update((data) {
    data['completed'] = {...completed, ...ids}.toList();
  });

  Future<void> dismissTip(String id) =>
      _update((data) => data['tipsSeen'] = {...tipsSeen, id}.toList());
}
