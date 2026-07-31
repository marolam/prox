import "package:prox/models/user_settings.dart";
import "package:prox/services/user_settings_service.dart";

class MatchSettingsService {
  MatchSettingsService._();
  static final MatchSettingsService instance = MatchSettingsService._();

  MatchDiscoverySettings get current =>
      UserSettingsService.instance.current.matchDiscovery;

  Stream<MatchDiscoverySettings> watchDiscovery() {
    return UserSettingsService.instance.watch().map((s) => s.matchDiscovery);
  }

  void setImmediateOnly(bool enabled) {
    final cur = current;
    UserSettingsService.instance.updateMatchDiscovery(
      cur.copyWith(immediateOnly: enabled),
    );
  }

  void setRadiusMiles(double miles) {
    UserSettingsService.instance.setRadiusMiles(miles);
  }

  void setPartyScope(MatchPartyScope scope) {
    final cur = current;
    UserSettingsService.instance.updateMatchDiscovery(
      cur.copyWith(partyScope: scope),
    );
  }

  void setBusinessOnly(bool enabled) {
    final cur = current;
    UserSettingsService.instance.updateMatchDiscovery(
      cur.copyWith(businessOnly: enabled),
    );
  }

  void setKeywordMode(KeywordMatchMode mode) {
    final cur = current;
    UserSettingsService.instance.updateMatchDiscovery(
      cur.copyWith(keywordMode: mode),
    );
  }

  void setListenRole(ListenMatchRole role) {
    final cur = current;
    UserSettingsService.instance.updateMatchDiscovery(
      cur.copyWith(listenRole: role),
    );
  }
}
