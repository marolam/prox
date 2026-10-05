import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/matching/background_matching_service.dart';

void main() {
  test('unreleased background service performs no Firebase or native setup', () async {
    // No Firebase app or platform channels are initialized in this test.
    expect(BackgroundMatchingService.available, isFalse);
    final service = BackgroundMatchingService.instance;
    expect(service.supported, isFalse);
    await service.start();
    await service.update(const BackgroundMatchingPreferences(enabled: true));
    await service.stopForSignOut();
    expect(service.preferences.enabled, isFalse);
  });
  test(
    'background collection needs opt-in and defaults to three quiet-hours alerts',
    () {
      final preferences = BackgroundMatchingPreferences.fromJson({});
      expect(preferences.enabled, isFalse);
      expect(preferences.dailyAlertLimit, 3);
      expect(preferences.quietHoursEnabled, isTrue);
      expect(preferences.copyWith(enabled: true).dailyAlertLimit, 3);
    },
  );

  test(
    'alert controls round trip and unsupported limits fall back to three',
    () {
      for (final limit in [1, 3, 6]) {
        final chosen = const BackgroundMatchingPreferences().copyWith(
          enabled: true,
          dailyAlertLimit: limit,
          quietHoursEnabled: false,
        );
        final restored = BackgroundMatchingPreferences.fromJson(
          chosen.toJson(),
        );
        expect(restored.enabled, isTrue);
        expect(restored.dailyAlertLimit, limit);
        expect(restored.quietHoursEnabled, isFalse);
      }
      for (final value in [-1, 0, 50, '6', null]) {
        expect(
          BackgroundMatchingPreferences.fromJson({
            'dailyAlertLimit': value,
          }).dailyAlertLimit,
          3,
        );
      }
    },
  );
}
