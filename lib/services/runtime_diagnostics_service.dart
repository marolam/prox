import "dart:async";

import "package:firebase_crashlytics/firebase_crashlytics.dart";
import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

/// Bounded local diagnostics; remote crash collection is an explicit preference.
class RuntimeDiagnosticsService extends ChangeNotifier {
  RuntimeDiagnosticsService._();
  static final instance = RuntimeDiagnosticsService._();
  static const preferenceKey = "share_crash_reports";

  final List<RuntimeIssue> _issues = [];
  List<RuntimeIssue> get issues => List.unmodifiable(_issues);
  bool _installed = false;
  bool _firebaseReady = false;
  bool _sharingEnabled = false;
  bool get sharingEnabled => _sharingEnabled;
  bool get supportsCrashReporting => !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  void installHandlers() {
    if (_installed) return;
    _installed = true;
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      record(details.exception, details.stack ?? StackTrace.current,
          operation: "Flutter framework", fatal: true);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, operation: "Asynchronous operation", fatal: true);
      return true;
    };
  }

  Future<void> initializeFirebase() async {
    if (_firebaseReady || !supportsCrashReporting) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      _sharingEnabled = preferences.getBool(preferenceKey) ?? false;
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(_sharingEnabled && kReleaseMode);
      _firebaseReady = true;
      notifyListeners();
    } catch (error, stack) {
      record(error, stack, operation: "Crash reporting initialization");
    }
  }

  Future<void> setSharingEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(preferenceKey, enabled);
    _sharingEnabled = enabled;
    if (_firebaseReady && supportsCrashReporting) {
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(enabled && kReleaseMode);
      if (!enabled) await FirebaseCrashlytics.instance.deleteUnsentReports();
    }
    notifyListeners();
  }

  void record(Object error, StackTrace stack,
      {required String operation, bool fatal = false}) {
    // Never collect user text, emails, credentials, URLs or location in logs.
    final kind = error.runtimeType.toString();
    _issues.insert(0, RuntimeIssue(
      operation: operation,
      kind: kind,
      occurredAt: DateTime.now().toUtc(),
      fatal: fatal,
    ));
    if (_issues.length > 50) _issues.removeRange(50, _issues.length);
    debugPrint("[Prox] $operation failed ($kind)");
    // Errors can arrive during build/layout; don't notify the UI synchronously.
    scheduleMicrotask(notifyListeners);
    if (_firebaseReady && _sharingEnabled && kReleaseMode && supportsCrashReporting) {
      unawaited(FirebaseCrashlytics.instance.recordError(
        kind, stack, reason: operation, fatal: fatal,
      ).catchError((Object _) {
        debugPrint("[Prox] Crash report delivery unavailable");
      }));
    }
  }
}

class RuntimeIssue {
  const RuntimeIssue({required this.operation, required this.kind,
    required this.occurredAt, required this.fatal});
  final String operation;
  final String kind;
  final DateTime occurredAt;
  final bool fatal;
}
