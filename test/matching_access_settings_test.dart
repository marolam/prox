import 'package:flutter_test/flutter_test.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/services/simple_mode/simple_mode_policy.dart';
import 'package:prox/services/user_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('public access and Party choice cannot leak between accounts', () async {
    final settings = UserSettingsService.forTesting();
    await settings.bindAccountSession('alice');
    settings.applyMatchingAccess(
      publicUnlocked: true,
      publicUnlockedAt: 100,
      partyScope: 'public',
    );
    expect(settings.publicMatchingUnlocked, isTrue);
    expect(settings.current.matchDiscovery.partyScope, MatchPartyScope.public);

    await settings.bindAccountSession('bob');
    expect(settings.publicMatchingUnlocked, isFalse);
    expect(settings.current.matchDiscovery.partyScope, MatchPartyScope.tree);
    settings.updateMatchDiscovery(
      settings.current.matchDiscovery.copyWith(
        partyScope: MatchPartyScope.partyOnly,
      ),
    );
    settings.applyMatchingAccess(
      publicUnlocked: true,
      publicUnlockedAt: 200,
      partyScope: 'partyOnly',
    );
    expect(
      settings.current.matchDiscovery.partyScope,
      MatchPartyScope.partyOnly,
    );

    await settings.bindAccountSession(null);
    expect(settings.publicMatchingUnlocked, isFalse);
    expect(settings.current.matchDiscovery.partyScope, MatchPartyScope.tree);
  });

  test('later unlock receipt does not undo an explicit Tree choice', () async {
    final settings = UserSettingsService.forTesting();
    await settings.bindAccountSession('alice');
    settings.applyMatchingAccess(
      publicUnlocked: true,
      publicUnlockedAt: 100,
      partyScope: 'public',
    );
    settings.updateMatchDiscovery(
      settings.current.matchDiscovery.copyWith(
        partyScope: MatchPartyScope.tree,
      ),
    );
    settings.applyMatchingAccess(publicUnlocked: true, publicUnlockedAt: 100);
    expect(settings.current.matchDiscovery.partyScope, MatchPartyScope.tree);
    settings.applyMatchingAccess(publicUnlocked: false, publicUnlockedAt: 100);
    expect(settings.publicMatchingUnlocked, isFalse);
    expect(settings.current.matchDiscovery.partyScope, MatchPartyScope.tree);
  });

  test('Simple Mode preserves every chosen scope and allows Party joining', () {
    expect(SimpleModePolicy.allowedHomeTabs, contains('Party'));
    for (final scope in [
      MatchPartyScope.partyOnly,
      MatchPartyScope.tree,
      MatchPartyScope.public,
    ]) {
      expect(
        SimpleModePolicy.lockedDiscoveryDefaults(
          const MatchDiscoverySettings.defaults().copyWith(partyScope: scope),
        ).partyScope,
        scope,
      );
    }
  });
}
