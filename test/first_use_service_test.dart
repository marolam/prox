import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/first_use_service.dart';
import 'package:prox/services/runtime_diagnostics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('only new accounts get an automatic welcome', () async {
    final fresh = FirstUseService('new');
    final existing = FirstUseService('existing');
    await fresh.load(autoWelcome: true);
    await existing.load();
    expect(fresh.enabled, isTrue);
    expect(fresh.welcomeSeen, isFalse);
    expect(existing.enabled, isFalse);
    expect(existing.welcomeSeen, isTrue);
    await existing.startTour(restart: true);
    expect(existing.enabled, isTrue);
    expect(existing.touring, isTrue);
  });

  test(
    'explore independently acknowledges welcome without launching tour',
    () async {
      final service = FirstUseService('explore');
      await service.load(autoWelcome: true);
      await service.welcome(startTour: false);
      expect(service.welcomeSeen, isTrue);
      expect(service.touring, isFalse);
      expect(service.completed, isEmpty);
      final restored = FirstUseService('explore');
      await restored.load(autoWelcome: true);
      expect(restored.welcomeSeen, isTrue);
    },
  );

  test(
    'reload preserves progress but does not interrupt with an automatic tour',
    () async {
      final service = FirstUseService('reload');
      await service.load(autoWelcome: true);
      await service.welcome(startTour: true);
      await service.moveTo(3);
      await service.dismissTip('Profile');
      await service.markComplete(['profile', 'keywords']);
      service.pauseTour();
      final restored = FirstUseService('reload');
      await restored.load();
      expect(restored.step, 3);
      expect(restored.touring, isFalse);
      expect(restored.tipsSeen, {'Profile'});
      expect(restored.completed, {'profile', 'keywords'});
      await restored.startTour();
      expect(restored.step, 3);
      expect(restored.touring, isTrue);
    },
  );

  test('account switches never share learning progress', () async {
    final one = FirstUseService('one');
    final two = FirstUseService('two');
    await one.startTour();
    await one.moveTo(4);
    await one.markComplete(['invitation']);
    await one.setHidden(true);
    await two.load(autoWelcome: true);
    expect(two.step, 0);
    expect(two.hidden, isFalse);
    expect(two.completed, isEmpty);
    expect(two.welcomeSeen, isFalse);
  });

  test(
    'concurrent updates are serialized without losing checklist entries',
    () async {
      final service = FirstUseService('concurrent');
      await service.load();
      await Future.wait([
        service.markComplete(['profile']),
        service.markComplete(['keywords']),
        service.dismissTip('Nearby'),
        service.moveTo(2),
      ]);
      final restored = FirstUseService('concurrent');
      await restored.load();
      expect(restored.completed, {'profile', 'keywords'});
      expect(restored.tipsSeen, {'Nearby'});
      expect(restored.step, 2);
    },
  );

  test('hidden checklist persists and replay restores it without erasing real work', () async {
    final service = FirstUseService('hidden');
    await service.startTour();
    await service.markComplete(['profile']);
    await service.moveTo(5);
    await service.dismissTip('Profile');
    await service.finishTour();
    await service.setHidden(true);
    final restored = FirstUseService('hidden');
    await restored.load();
    expect(restored.hidden, isTrue);
    expect(restored.finished, isTrue);
    await restored.startTour(restart: true);
    expect(restored.hidden, isFalse);
    expect(restored.finished, isFalse);
    expect(restored.step, 0);
    expect(restored.tipsSeen, isEmpty);
    expect(restored.completed, {'profile'});
  });

  test(
    'invalid stored data is reported, not silently treated as completed',
    () async {
      final service = FirstUseService('corrupt');
      SharedPreferences.setMockInitialValues({
        service.storageKey: '{"step":99}',
      });
      await expectLater(service.load(), throwsFormatException);
      expect(service.ready, isFalse);
      expect(
        RuntimeDiagnosticsService.instance.issues.first.operation,
        'Load first-use guidance',
      );
      SharedPreferences.setMockInitialValues({});
      await service.load(autoWelcome: true);
      expect(service.ready, isTrue);
      expect(service.welcomeSeen, isFalse);
    },
  );

  test(
    'invalid step fails explicitly and does not poison later writes',
    () async {
      final service = FirstUseService('invalid-step');
      await service.load();
      await expectLater(service.moveTo(6), throwsRangeError);
      await service.moveTo(2);
      expect(service.step, 2);
      final preferences = await SharedPreferences.getInstance();
      final stored = jsonDecode(preferences.getString(service.storageKey)!);
      expect(stored['step'], 2);
      expect(stored.keys, isNot(contains('invitationsSent')));
    },
  );
}
