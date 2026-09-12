import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prox/services/app_lifecycle_service.dart';
import 'package:prox/services/location_privacy_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLifecycleService.instance.didChangeAppLifecycleState(
      AppLifecycleState.resumed,
    );
  });

  test('saved opt-out survives a fresh service without reading GPS', () async {
    var removals = 0;
    LocationPrivacyService create() => LocationPrivacyService.forTesting(
      preferences: SharedPreferences.getInstance,
      expirePresence: () async {
        removals++;
      },
    );
    final first = create();
    expect(first.mayReadLocation, isFalse);
    await first.ensureLoaded();
    expect(first.mayReadLocation, isTrue);
    await first.setLocationEnabled(false);
    final restarted = create();
    await restarted.ensureLoaded();
    expect(restarted.locationEnabled, isFalse);
    expect(restarted.mayReadLocation, isFalse);
    expect(removals, 1);
    first.dispose();
    restarted.dispose();
  });

  test(
    'opt-out stops work immediately while preferences are still loading',
    () async {
      final pending = Completer<SharedPreferences>();
      final service = LocationPrivacyService.forTesting(
        preferences: () => pending.future,
        expirePresence: () async {},
      );
      var observed = true;
      service.addListener(() {
        observed = service.locationEnabled;
      });
      final loading = service.ensureLoaded();
      final disabled = service.setLocationEnabled(false);
      expect(service.mayReadLocation, isFalse);
      expect(observed, isFalse);
      pending.complete(await SharedPreferences.getInstance());
      await Future.wait([loading, disabled]);
      expect(service.locationEnabled, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          LocationPrivacyService.preferenceKey,
        ),
        isFalse,
      );
      service.dispose();
    },
  );

  test(
    'rapid changes persist in order and background use stays disabled',
    () async {
      final service = LocationPrivacyService.forTesting(
        preferences: SharedPreferences.getInstance,
        expirePresence: () async {},
      );
      await Future.wait([
        service.setLocationEnabled(false),
        service.setLocationEnabled(true),
        service.setLocationEnabled(false),
      ]);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          LocationPrivacyService.preferenceKey,
        ),
        isFalse,
      );
      await service.setLocationEnabled(true);
      AppLifecycleService.instance.didChangeAppLifecycleState(
        AppLifecycleState.paused,
      );
      expect(service.mayReadLocation, isFalse);
      AppLifecycleService.instance.didChangeAppLifecycleState(
        AppLifecycleState.resumed,
      );
      expect(service.mayReadLocation, isTrue);
      service.dispose();
    },
  );
}
