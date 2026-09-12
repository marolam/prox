import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum DeviceLocationFailure {
  permissionDenied,
  servicesDisabled,
  timedOut,
  unavailable,
  cancelled,
}

class DeviceLocationResult {
  const DeviceLocationResult({
    this.position,
    this.cached = false,
    this.failure,
  });

  final Position? position;
  final bool cached;
  final DeviceLocationFailure? failure;
}

/// Bounded foreground acquisition. Never requests permission or starts a stream.
/// Callers supply their account/lifecycle/privacy guard and recheck before use.
class DeviceLocationResolver {
  DeviceLocationResolver._({
    required Future<bool> Function() serviceEnabled,
    required Future<LocationPermission> Function() permission,
    required Future<Position> Function(LocationSettings) currentPosition,
    required Future<Position?> Function() lastKnownPosition,
    required bool Function() isAndroid,
    DateTime Function()? now,
  }) : _serviceEnabled = serviceEnabled,
       _permission = permission,
       _currentPosition = currentPosition,
       _lastKnownPosition = lastKnownPosition,
       _isAndroid = isAndroid,
       _now = now ?? DateTime.now;

  @visibleForTesting
  factory DeviceLocationResolver.forTesting({
    required Future<bool> Function() serviceEnabled,
    required Future<LocationPermission> Function() permission,
    required Future<Position> Function(LocationSettings) currentPosition,
    required Future<Position?> Function() lastKnownPosition,
    required bool isAndroid,
    required DateTime Function() now,
  }) => DeviceLocationResolver._(
    serviceEnabled: serviceEnabled,
    permission: permission,
    currentPosition: currentPosition,
    lastKnownPosition: lastKnownPosition,
    isAndroid: () => isAndroid,
    now: now,
  );

  static final instance = DeviceLocationResolver._(
    serviceEnabled: Geolocator.isLocationServiceEnabled,
    permission: Geolocator.checkPermission,
    currentPosition: (settings) =>
        Geolocator.getCurrentPosition(locationSettings: settings),
    lastKnownPosition: Geolocator.getLastKnownPosition,
    isAndroid: () => !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
  );

  final Future<bool> Function() _serviceEnabled;
  final Future<LocationPermission> Function() _permission;
  final Future<Position> Function(LocationSettings) _currentPosition;
  final Future<Position?> Function() _lastKnownPosition;
  final bool Function() _isAndroid;
  final DateTime Function() _now;
  final Map<(LocationAccuracy, Duration, bool), Future<Position>> _pending = {};
  DateTime? _lastAndroidFallback;

  Future<DeviceLocationResult> resolve({
    LocationAccuracy accuracy = LocationAccuracy.medium,
    Duration timeLimit = const Duration(seconds: 10),
    Duration maxCachedAge = const Duration(minutes: 3),
    bool Function()? isCurrent,
    bool bypassFallbackCooldown = false,
    double maxAccuracyMeters = 300,
  }) async {
    bool active() => isCurrent?.call() ?? true;
    const cancelled = DeviceLocationResult(
      failure: DeviceLocationFailure.cancelled,
    );
    if (!active()) return cancelled;
    final limit = Duration(
      milliseconds: timeLimit.inMilliseconds.clamp(1, 10000),
    );
    final freshAge = maxCachedAge < const Duration(minutes: 2)
        ? maxCachedAge
        : const Duration(minutes: 2);
    final gate = await _checkAccess();
    if (!active()) return cancelled;
    if (gate != null) return DeviceLocationResult(failure: gate);

    DeviceLocationFailure failure = DeviceLocationFailure.unavailable;
    try {
      final position = await _readCurrent(accuracy, limit, false);
      if (!active()) return cancelled;
      if (_usable(position, freshAge, maxAccuracyMeters)) {
        return DeviceLocationResult(position: position);
      }
    } catch (error) {
      if (!active()) return cancelled;
      failure = _failureFor(error);
      if (_accessFailure(failure))
        return DeviceLocationResult(failure: failure);
    }

    if (!active()) return cancelled;
    final cachedGate = await _checkAccess();
    if (!active()) return cancelled;
    if (cachedGate != null) return DeviceLocationResult(failure: cachedGate);
    try {
      final cached = await _lastKnownPosition().timeout(
        const Duration(seconds: 3),
      );
      if (!active()) return cancelled;
      if (cached != null && _usable(cached, maxCachedAge, maxAccuracyMeters)) {
        return DeviceLocationResult(position: cached, cached: true);
      }
    } catch (error) {
      if (!active()) return cancelled;
      final cachedFailure = _failureFor(error);
      if (_accessFailure(cachedFailure)) {
        return DeviceLocationResult(failure: cachedFailure);
      }
    }

    if (!active()) return cancelled;
    if (!_isAndroid()) return DeviceLocationResult(failure: failure);
    final fallbackKey = (LocationAccuracy.high, limit, true);
    // Recheck OS access after a failed acquisition; a provider retry must not
    // follow permission revocation or location services being switched off.
    final fallbackGate = await _checkAccess();
    if (!active()) return cancelled;
    if (fallbackGate != null) {
      return DeviceLocationResult(failure: fallbackGate);
    }
    final previousFallback = _lastAndroidFallback;
    final ownsFallback = !_pending.containsKey(fallbackKey);
    if (!bypassFallbackCooldown &&
        ownsFallback &&
        previousFallback != null &&
        _now().difference(previousFallback) < const Duration(minutes: 1)) {
      return DeviceLocationResult(failure: failure);
    }
    _lastAndroidFallback = _now();
    if (ownsFallback) {
      debugPrint('[Prox] Android location fallback started (${failure.name})');
    }
    try {
      final position = await _readCurrent(LocationAccuracy.high, limit, true);
      if (!active()) {
        if (ownsFallback)
          debugPrint('[Prox] Android location fallback cancelled');
        return cancelled;
      }
      if (_usable(position, freshAge, maxAccuracyMeters)) {
        if (ownsFallback)
          debugPrint('[Prox] Android location fallback succeeded');
        return DeviceLocationResult(position: position);
      }
    } catch (error) {
      if (!active()) {
        if (ownsFallback)
          debugPrint('[Prox] Android location fallback cancelled');
        return cancelled;
      }
      failure = _failureFor(error);
    }
    if (ownsFallback) {
      debugPrint('[Prox] Android location fallback failed (${failure.name})');
    }
    return DeviceLocationResult(failure: failure);
  }

  Future<DeviceLocationFailure?> _checkAccess() async {
    try {
      final access = await Future.wait<Object>([
        _serviceEnabled().timeout(const Duration(seconds: 5)),
        _permission().timeout(const Duration(seconds: 5)),
      ]);
      if (access[0] != true) return DeviceLocationFailure.servicesDisabled;
      if (access[1] != LocationPermission.always &&
          access[1] != LocationPermission.whileInUse) {
        return DeviceLocationFailure.permissionDenied;
      }
      return null;
    } catch (error) {
      return _failureFor(error);
    }
  }

  Future<Position> _readCurrent(
    LocationAccuracy accuracy,
    Duration timeLimit,
    bool forceLocationManager,
  ) {
    final key = (accuracy, timeLimit, forceLocationManager);
    final pending = _pending[key];
    if (pending != null) return pending;
    final LocationSettings settings = forceLocationManager
        ? AndroidSettings(
            accuracy: accuracy,
            forceLocationManager: true,
            distanceFilter: 0,
            timeLimit: timeLimit,
          )
        : LocationSettings(
            accuracy: accuracy,
            distanceFilter: 0,
            timeLimit: timeLimit,
          );
    // Geolocator's timeLimit cancels its native one-shot request on timeout.
    // An outer Future.timeout alone would leave that native work running.
    late final Future<Position> request;
    request = Future<Position>.sync(() => _currentPosition(settings))
        .whenComplete(() {
          if (identical(_pending[key], request)) _pending.remove(key);
        });
    _pending[key] = request;
    return request;
  }

  bool _usable(Position position, Duration maxAge, double maxAccuracyMeters) {
    final age = _now().difference(position.timestamp);
    return position.latitude.isFinite &&
        position.longitude.isFinite &&
        position.latitude.abs() <= 90 &&
        position.longitude.abs() <= 180 &&
        age >= const Duration(minutes: -1) &&
        age <= maxAge &&
        position.accuracy.isFinite &&
        position.accuracy >= 0 &&
        position.accuracy <= maxAccuracyMeters;
  }

  DeviceLocationFailure _failureFor(Object error) {
    if (error is PermissionDeniedException) {
      return DeviceLocationFailure.permissionDenied;
    }
    if (error is LocationServiceDisabledException) {
      return DeviceLocationFailure.servicesDisabled;
    }
    if (error is TimeoutException) return DeviceLocationFailure.timedOut;
    return DeviceLocationFailure.unavailable;
  }

  bool _accessFailure(DeviceLocationFailure failure) =>
      failure == DeviceLocationFailure.permissionDenied ||
      failure == DeviceLocationFailure.servicesDisabled;
}
