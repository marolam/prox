import "dart:async";

import "package:firebase_auth/firebase_auth.dart";
import "package:prox/services/user_profile_service.dart";
import "package:prox/services/user_settings_service.dart";

enum SimpleModeStage {
  profile,
  match,
  chat,
  meetup,
  rate,
  unlocked,
}

class SimpleModeState {
  const SimpleModeState({
    required this.stage,
  });

  const SimpleModeState.initial() : stage = SimpleModeStage.profile;

  final SimpleModeStage stage;

  bool get isUnlocked => stage == SimpleModeStage.unlocked;
}

class SimpleModeService {
  SimpleModeService._();
  static final SimpleModeService instance = SimpleModeService._();

  static const bool isEnabledByDefault = true;

  final StreamController<SimpleModeState> _controller =
      StreamController<SimpleModeState>.broadcast();

  SimpleModeState _last = const SimpleModeState.initial();

  Stream<SimpleModeState> watch() {
    Future<void>.microtask(refresh);
    return _controller.stream;
  }

  Future<void> refresh() async {
    await UserSettingsService.instance.ensureLoaded();
    final settings = UserSettingsService.instance.current;
    if (!settings.simpleModeEnabled || settings.simpleModeCompleted) {
      _emit(const SimpleModeState(stage: SimpleModeStage.unlocked));
      return;
    }

    var idx = settings.simpleModeStageIndex;
    if (idx <= 0 && await _hasMinimumProfile()) {
      idx = 1;
      UserSettingsService.instance.setSimpleModeStageIndex(idx);
    }

    final stage = _fromIndex(idx);
    _emit(SimpleModeState(stage: stage));
  }

  Future<bool> _hasMinimumProfile() async {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? "").trim();
    if (uid.isEmpty) return false;
    final profile = await UserProfileService.instance.getProfileOnce(uid);
    if (profile == null) return false;
    final hasName = (profile.displayName ?? "").trim().isNotEmpty;
    return hasName && profile.hasMinimumKeywords;
  }

  void _emit(SimpleModeState state) {
    _last = state;
    if (!_controller.isClosed) {
      _controller.add(_last);
    }
  }

  SimpleModeStage _fromIndex(int idx) {
    if (idx <= 0) return SimpleModeStage.profile;
    if (idx == 1) return SimpleModeStage.match;
    if (idx == 2) return SimpleModeStage.chat;
    if (idx == 3) return SimpleModeStage.meetup;
    if (idx == 4) return SimpleModeStage.rate;
    return SimpleModeStage.unlocked;
  }
}
