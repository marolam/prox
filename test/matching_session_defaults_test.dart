import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/services/user_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cold launch does not restore a saved active mode before account binding',
    () async {
      final saved = const UserSettings.defaults().copyWith(
        matchDiscovery: const MatchDiscoverySettings.defaults().copyWith(
          modeKind: MatchingModeKind.travel,
          normalMode: NormalMatchMode.active,
        ),
      );
      SharedPreferences.setMockInitialValues({
        'user_settings': jsonEncode(saved.toJson()),
      });
      await UserSettingsService.instance.ensureLoaded();
      expect(
        UserSettingsService.instance.current.matchDiscovery.modeKind,
        MatchingModeKind.normal,
      );
      expect(
        UserSettingsService.instance.current.matchDiscovery.normalMode,
        NormalMatchMode.passive,
      );
    },
  );

  for (final kind in MatchingModeKind.values) {
    test(
      'new account session resets $kind to Normal Passive and preserves criteria',
      () async {
        final service = UserSettingsService.forTesting(
          initial: const UserSettings.defaults().copyWith(
            matchDiscovery: const MatchDiscoverySettings.defaults().copyWith(
              modeKind: kind,
              normalMode: NormalMatchMode.active,
              radiusMiles: 4,
              treasureRadiusMiles: 8,
              keywordMode: KeywordMatchMode.strict,
            ),
          ),
        );
        await service.bindAccountSession('me');
        final settings = service.current.matchDiscovery;
        expect(settings.modeKind, MatchingModeKind.normal);
        expect(settings.normalMode, NormalMatchMode.passive);
        expect(settings.radiusMiles, 4);
        expect(settings.treasureRadiusMiles, 8);
        expect(settings.keywordMode, KeywordMatchMode.strict);
        service.setNormalMatchMode(NormalMatchMode.active);
        await service.ensureLoaded();
        expect(
          service.current.matchDiscovery.normalMode,
          NormalMatchMode.active,
          reason:
              'loading settings within a session must not reset deliberate activation',
        );
        await service.bindAccountSession('another-account');
        expect(
          service.current.matchDiscovery.normalMode,
          NormalMatchMode.passive,
        );
      },
    );
  }
}
