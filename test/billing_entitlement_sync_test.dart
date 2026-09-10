import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/services/billing_entitlement_sync_service.dart';
import 'package:prox/services/user_settings_service.dart';

const _granted = <String, dynamic>{
  'highRadiusUnlocked': true,
  'singleKeywordMatchModeUnlocked': true,
  'reciprocalKeywordMatchModeUnlocked': true,
  'keywordChainMatchModeUnlocked': true,
};

/// Retains callbacks to simulate an already in-flight provider event even after
/// cancellation; the session generation must reject it independently.
class _LateStream extends Stream<Map<String, dynamic>?> {
  final _controller = StreamController<Map<String, dynamic>?>();
  void Function(Map<String, dynamic>?)? _data;
  Function? _error;

  @override
  StreamSubscription<Map<String, dynamic>?> listen(
    void Function(Map<String, dynamic>?)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _data = onData;
    _error = onError;
    return _controller.stream.listen(onData, onError: onError, onDone: onDone);
  }

  void emit(Map<String, dynamic>? value) => _data?.call(value);
  void fail() => Function.apply(_error!, [
    StateError('stream unavailable'),
    StackTrace.current,
  ]);
}

class _Harness {
  _Harness({UserSettings initial = const UserSettings.defaults()}) {
    settings = UserSettingsService.forTesting(
      initial: initial,
      proPreviewAllowed: () => true,
      persistSettings: (value) async => saved.add(value),
    );
    sync = BillingEntitlementSyncService(
      currentUid: () => uid,
      watchEntitlements: (owner) {
        final stream = _LateStream();
        streams.add((uid: owner, stream: stream));
        return stream;
      },
      settings: settings,
      onError: (error, _) => errors.add(error),
    );
  }
  String? uid = 'alice';
  late final UserSettingsService settings;
  late final BillingEntitlementSyncService sync;
  final saved = <UserSettings>[];
  final errors = <Object>[];
  final streams = <({String uid, _LateStream stream})>[];
  _LateStream get active => streams.last.stream;
  Future<void> close() async {
    await sync.dispose();
    await settings.dispose();
  }
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'restored signed-in identity subscribes once and cached grants start locked',
    () async {
      final h = _Harness(
        initial: const UserSettings.defaults().copyWith(
          textScaleFactor: 1.4,
          matchDiscovery: const MatchDiscoverySettings.defaults().copyWith(
            highRadiusUnlocked: true,
          ),
        ),
      );
      addTearDown(h.close);
      await h.sync.bindAccount('alice');
      await h.sync.bindAccount('alice');
      expect(h.streams, hasLength(1));
      expect(h.settings.current.matchDiscovery.highRadiusUnlocked, isFalse);
      expect(h.settings.current.textScaleFactor, 1.4);
      h.active.emit(_granted);
      expect(h.settings.current.matchDiscovery.highRadiusUnlocked, isTrue);
    },
  );

  test(
    'server refund atomically revokes flags and clamps the active keyword mode and radius',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.sync.bindAccount('alice');
      h.active.emit(_granted);
      h.settings.updateMatchDiscovery(
        h.settings.current.matchDiscovery.copyWith(
          businessOnly: true,
          radiusMiles: 30,
          keywordMode: KeywordMatchMode.keywordChain,
        ),
      );
      final events = <UserSettings>[];
      final subscription = h.settings.watch().listen(events.add);
      addTearDown(subscription.cancel);
      await _tick();
      events.clear();
      h.active.emit(const {});
      await _tick();
      expect(events, hasLength(1));
      final discovery = events.single.matchDiscovery;
      expect(discovery.highRadiusUnlocked, isFalse);
      expect(discovery.singleKeywordMatchUnlocked, isFalse);
      expect(discovery.reciprocalMatchUnlocked, isFalse);
      expect(discovery.keywordChainUnlocked, isFalse);
      expect(discovery.keywordMode, KeywordMatchMode.similar);
      expect(discovery.radiusMiles, 15);
      // A stale one-shot request or form snapshot cannot restore refunded grants.
      h.settings.setHighRadiusUnlocked(true);
      h.settings.setSingleKeywordMatchUnlocked(true);
      h.settings.setReciprocalMatchUnlocked(true);
      h.settings.setKeywordChainUnlocked(true);
      h.settings.updateMatchDiscovery(
        discovery.copyWith(highRadiusUnlocked: true, radiusMiles: 30),
      );
      expect(h.settings.current.matchDiscovery, discovery);
    },
  );

  test(
    'late account events and errors cannot replace current access, including switching back to the same UID',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.sync.bindAccount('alice');
      final oldAlice = h.active;
      h.uid = 'bob';
      oldAlice.emit(_granted);
      oldAlice.fail();
      expect(h.settings.current.matchDiscovery.highRadiusUnlocked, isFalse);
      expect(h.errors, isEmpty);
      await h.sync.bindAccount('bob');
      h.uid = 'alice';
      await h.sync.bindAccount('alice');
      oldAlice.emit(_granted);
      oldAlice.fail();
      expect(h.settings.current.matchDiscovery.highRadiusUnlocked, isFalse);
      expect(h.errors, isEmpty);
      h.active.emit(_granted);
      expect(h.settings.current.matchDiscovery.highRadiusUnlocked, isTrue);
    },
  );

  test(
    'signout and account changes remove private notes and prompt history while retaining device preferences',
    () async {
      final h = _Harness(
        initial: const UserSettings.defaults().copyWith(
          textScaleFactor: 1.5,
          matchSoundVolume: 0.4,
        ),
      );
      addTearDown(h.close);
      await h.sync.bindAccount('alice');
      h.settings.setBusinessAvatarNote('Private Alice reply');
      h.settings.markBusinessPromptSeenFor('alice-peer');
      h.active.emit(_granted);
      h.uid = 'bob';
      await h.sync.bindAccount('bob');
      expect(h.settings.current.businessAvatarNote, isNull);
      expect(h.settings.current.seenBusinessPrompts, isEmpty);
      expect(h.settings.current.matchDiscovery.highRadiusUnlocked, isFalse);
      expect(h.settings.current.textScaleFactor, 1.5);
      expect(h.settings.current.matchSoundVolume, 0.4);
      h.settings.setBusinessAvatarNote('Private Bob reply');
      h.settings.markBusinessPromptSeenFor('bob-peer');
      h.active.emit(_granted);
      h.uid = null;
      await h.sync.bindAccount(null);
      expect(h.settings.current.businessAvatarNote, isNull);
      expect(h.settings.current.seenBusinessPrompts, isEmpty);
      expect(h.saved.last.businessAvatarNote, isNull);
      expect(h.saved.last.seenBusinessPrompts, isEmpty);
      expect(h.saved.last.matchDiscovery.highRadiusUnlocked, isFalse);
    },
  );

  test(
    'current stream failure locks paid access and a later server snapshot recovers',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.sync.bindAccount('alice');
      h.active.emit(_granted);
      h.active.fail();
      expect(h.settings.current.matchDiscovery.highRadiusUnlocked, isFalse);
      expect(h.errors, hasLength(1));
      h.active.emit(_granted);
      expect(h.settings.current.matchDiscovery.highRadiusUnlocked, isTrue);
      h.active.emit(null);
      expect(h.settings.current.matchDiscovery.highRadiusUnlocked, isFalse);
    },
  );

  test(
    'unbound injected matching settings retain their isolated test configuration',
    () async {
      final settings = UserSettingsService.forTesting();
      addTearDown(settings.dispose);
      settings.setSingleKeywordMatchUnlocked(true);
      expect(
        settings.current.matchDiscovery.singleKeywordMatchUnlocked,
        isTrue,
      );
    },
  );
}
