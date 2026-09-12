import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:prox/services/device_location_resolver.dart';

final now = DateTime.utc(2026, 9, 8, 12);

Position fix({
  Duration age = Duration.zero,
  double latitude = 40,
  double longitude = -74,
  double accuracy = 20,
}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: now.subtract(age),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class LocationHarness {
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  DateTime clock = now;
  int accessChecks = 0;
  int cachedReads = 0;
  Position? cached;
  final List<LocationSettings> requests = [];
  Future<Position> Function(LocationSettings) current = (_) async => fix();
  Future<Position?> Function()? lastKnown;

  DeviceLocationResolver resolver({bool android = true}) =>
      DeviceLocationResolver.forTesting(
        serviceEnabled: () async {
          accessChecks++;
          return enabled;
        },
        permission: () async => permission,
        currentPosition: (settings) {
          requests.add(settings);
          return current(settings);
        },
        lastKnownPosition: () async {
          cachedReads++;
          return lastKnown != null ? await lastKnown!() : cached;
        },
        isAndroid: android,
        now: () => clock,
      );
}

void main() {
  test(
    'a fresh fix returns without cached reads or provider retries',
    () async {
      final harness = LocationHarness();
      final result = await harness.resolver().resolve();
      expect(result.position, isNotNull);
      expect(result.cached, isFalse);
      expect(result.failure, isNull);
      expect(harness.requests, hasLength(1));
      expect(harness.requests.single.accuracy, LocationAccuracy.medium);
      expect(harness.requests.single.timeLimit, const Duration(seconds: 10));
      expect(harness.cachedReads, 0);
    },
  );

  test(
    'a timeout uses a fresh cached fix without another GPS request',
    () async {
      final harness = LocationHarness()
        ..cached = fix(age: const Duration(minutes: 2))
        ..current = (_) async => throw TimeoutException('provider');
      final result = await harness.resolver().resolve();
      expect(result.position, same(harness.cached));
      expect(result.cached, isTrue);
      expect(harness.requests, hasLength(1));
    },
  );

  test(
    'Android recovers from a failed provider with bounded high accuracy',
    () async {
      final harness = LocationHarness()
        ..current = (settings) async {
          if (settings is AndroidSettings && settings.forceLocationManager) {
            return fix();
          }
          throw TimeoutException('provider');
        };
      final result = await harness.resolver().resolve(
        timeLimit: const Duration(minutes: 1),
      );
      expect(result.position, isNotNull);
      expect(result.cached, isFalse);
      expect(harness.requests, hasLength(2));
      final fallback = harness.requests.last as AndroidSettings;
      expect(fallback.forceLocationManager, isTrue);
      expect(fallback.accuracy, LocationAccuracy.high);
      expect(fallback.timeLimit, const Duration(seconds: 10));
      expect(fallback.foregroundNotificationConfig, isNull);
    },
  );

  test('iOS does not run an Android provider fallback', () async {
    final harness = LocationHarness()
      ..current = (_) async => throw TimeoutException('provider');
    final result = await harness.resolver(android: false).resolve();
    expect(result.position, isNull);
    expect(result.failure, DeviceLocationFailure.timedOut);
    expect(harness.requests, hasLength(1));
  });

  for (final permission in [
    LocationPermission.denied,
    LocationPermission.deniedForever,
  ]) {
    test('$permission never reads current or cached coordinates', () async {
      final harness = LocationHarness()..permission = permission;
      final result = await harness.resolver().resolve();
      expect(result.failure, DeviceLocationFailure.permissionDenied);
      expect(harness.requests, isEmpty);
      expect(harness.cachedReads, 0);
    });
  }

  test('disabled services never read current or cached coordinates', () async {
    final harness = LocationHarness()..enabled = false;
    final result = await harness.resolver().resolve();
    expect(result.failure, DeviceLocationFailure.servicesDisabled);
    expect(harness.requests, isEmpty);
    expect(harness.cachedReads, 0);
  });

  for (final error in <Exception>[
    const PermissionDeniedException(null),
    const LocationServiceDisabledException(),
  ]) {
    test(
      'a provider access error stops all fallback: ${error.runtimeType}',
      () async {
        final harness = LocationHarness()..current = (_) async => throw error;
        final result = await harness.resolver().resolve();
        expect(result.position, isNull);
        expect(harness.requests, hasLength(1));
        expect(harness.cachedReads, 0);
      },
    );
  }

  test(
    'services switched off during acquisition prevent platform retry',
    () async {
      final harness = LocationHarness();
      harness.current = (_) async {
        harness.enabled = false;
        throw TimeoutException('provider');
      };
      final result = await harness.resolver().resolve();
      expect(result.failure, DeviceLocationFailure.servicesDisabled);
      expect(harness.requests, hasLength(1));
      expect(harness.cachedReads, 0);
    },
  );

  test(
    'permission revoked during acquisition prevents platform retry',
    () async {
      final harness = LocationHarness();
      harness.current = (_) async {
        harness.permission = LocationPermission.denied;
        throw TimeoutException('provider');
      };
      final result = await harness.resolver().resolve();
      expect(result.failure, DeviceLocationFailure.permissionDenied);
      expect(harness.requests, hasLength(1));
      expect(harness.cachedReads, 0);
    },
  );

  test('a cancelled caller never starts an OS access check', () async {
    final harness = LocationHarness();
    final result = await harness.resolver().resolve(isCurrent: () => false);
    expect(result.failure, DeviceLocationFailure.cancelled);
    expect(harness.accessChecks, 0);
    expect(harness.requests, isEmpty);
  });

  test(
    'account/privacy change discards a pending fix and stops fallback',
    () async {
      final harness = LocationHarness();
      final pending = Completer<Position>();
      final started = Completer<void>();
      harness.current = (_) {
        started.complete();
        return pending.future;
      };
      var active = true;
      final result = harness.resolver().resolve(isCurrent: () => active);
      await started.future;
      active = false;
      pending.complete(fix());
      expect((await result).failure, DeviceLocationFailure.cancelled);
      expect(harness.requests, hasLength(1));
      expect(harness.cachedReads, 0);
    },
  );

  test('privacy change during cached lookup stops Android fallback', () async {
    final harness = LocationHarness()
      ..current = (_) async => throw TimeoutException('provider');
    var active = true;
    harness.lastKnown = () async {
      active = false;
      return null;
    };
    final result = await harness.resolver().resolve(isCurrent: () => active);
    expect(result.failure, DeviceLocationFailure.cancelled);
    expect(harness.requests, hasLength(1));
  });

  final unusable = <String, Position>{
    'stale timestamp': fix(age: const Duration(minutes: 16)),
    'future timestamp': fix(age: const Duration(minutes: -2)),
    'non-finite latitude': fix(latitude: double.nan),
    'invalid longitude': fix(longitude: 181),
    'poor accuracy': fix(accuracy: 301),
    'invalid accuracy': fix(accuracy: double.nan),
  };
  for (final entry in unusable.entries) {
    test('rejects ${entry.key} from every location source', () async {
      final harness = LocationHarness()
        ..cached = entry.value
        ..current = (_) async => entry.value;
      final result = await harness.resolver().resolve();
      expect(result.position, isNull);
      expect(result.failure, DeviceLocationFailure.unavailable);
      expect(harness.requests, hasLength(2));
    });
  }

  test(
    'stale current fixes may only return as an explicitly allowed cache',
    () async {
      final old = fix(age: const Duration(minutes: 5));
      final harness = LocationHarness()
        ..cached = old
        ..current = (_) async => old;
      final result = await harness.resolver().resolve(
        maxCachedAge: const Duration(minutes: 15),
      );
      expect(result.position, same(old));
      expect(result.cached, isTrue);
      expect(harness.cachedReads, 1);
      final nearby = await harness.resolver().resolve();
      expect(nearby.position, isNull);
    },
  );

  test(
    'concurrent callers share one native request but retain separate guards',
    () async {
      final harness = LocationHarness();
      final pending = Completer<Position>();
      final started = Completer<void>();
      harness.current = (_) {
        if (!started.isCompleted) started.complete();
        return pending.future;
      };
      final resolver = harness.resolver();
      var active = true;
      final cancelled = resolver.resolve(isCurrent: () => active);
      final current = resolver.resolve(isCurrent: () => true);
      await started.future;
      await Future<void>.delayed(Duration.zero);
      active = false;
      pending.complete(fix());
      expect((await cancelled).failure, DeviceLocationFailure.cancelled);
      expect((await current).position, isNotNull);
      expect(harness.requests, hasLength(1));
    },
  );

  test(
    'background cadence limits provider fallback while manual retry can bypass',
    () async {
      final harness = LocationHarness()
        ..current = (_) async => throw TimeoutException('provider');
      final resolver = harness.resolver();
      await resolver.resolve();
      expect(harness.requests, hasLength(2));
      await resolver.resolve();
      expect(harness.requests, hasLength(3));
      await resolver.resolve(bypassFallbackCooldown: true);
      expect(harness.requests, hasLength(5));
      harness.clock = now.add(const Duration(minutes: 1));
      await resolver.resolve();
      expect(harness.requests, hasLength(7));
    },
  );
}
