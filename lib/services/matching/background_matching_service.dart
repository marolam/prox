import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/services/matching/matching_mode_service.dart';
import 'package:prox/services/location_privacy_service.dart';
import 'package:prox/services/user_settings_service.dart';

class BackgroundMatchingPreferences {
  const BackgroundMatchingPreferences({
    this.enabled = false,
    this.dailyAlertLimit = 3,
    this.quietHoursEnabled = true,
  });
  final bool enabled;
  final int dailyAlertLimit;
  final bool quietHoursEnabled;
  factory BackgroundMatchingPreferences.fromJson(Map<String, dynamic> json) =>
      BackgroundMatchingPreferences(
        enabled: json['enabled'] == true,
        dailyAlertLimit: const [1, 3, 6].contains(json['dailyAlertLimit'])
            ? json['dailyAlertLimit'] as int
            : 3,
        quietHoursEnabled: json['quietHoursEnabled'] != false,
      );
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'dailyAlertLimit': dailyAlertLimit,
    'quietHoursEnabled': quietHoursEnabled,
  };
  BackgroundMatchingPreferences copyWith({
    bool? enabled,
    int? dailyAlertLimit,
    bool? quietHoursEnabled,
  }) => BackgroundMatchingPreferences.fromJson({
    ...toJson(),
    if (enabled != null) 'enabled': enabled,
    if (dailyAlertLimit != null) 'dailyAlertLimit': dailyAlertLimit,
    if (quietHoursEnabled != null) 'quietHoursEnabled': quietHoursEnabled,
  });
}

class BackgroundMatchingService extends ChangeNotifier
    with WidgetsBindingObserver {
  BackgroundMatchingService._();
  static final instance = BackgroundMatchingService._();
  // Enable only in builds whose background backend has been deployed.
  static const available = bool.fromEnvironment(
    'PROX_BACKGROUND_MATCHING_AVAILABLE',
    defaultValue: false,
  );
  static const _channel = MethodChannel('prox/background_matching');
  BackgroundMatchingPreferences preferences =
      const BackgroundMatchingPreferences();
  bool get supported =>
      available &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool busy = false;
  String status = 'Background matching is off.';
  String? _uid;
  String _deviceId = '';
  int _generation = 0;
  int _configurationRevision = 0;
  bool _signingOut = false;
  Future<void> _queue = Future.value();
  Future<void>? _starting;
  String? _lastConfiguration;
  String? _lastObservedConfiguration;
  StreamSubscription<User?>? _auth;
  StreamSubscription<UserSettings>? _settings;

  Future<void> start() => _starting ??= _start();
  Future<void> _start() async {
    if (!supported) return;
    await LocationPrivacyService.instance.ensureLoaded();
    WidgetsBinding.instance.addObserver(this);
    LocationPrivacyService.instance.addListener(_changed);
    _settings = UserSettingsService.instance.watch().listen((_) => _changed());
    _auth = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid != _uid) unawaited(_bind(user?.uid));
    });
    await _bind(FirebaseAuth.instance.currentUser?.uid);
  }

  Future<void> _bind(String? uid) async {
    final generation = ++_generation;
    _uid = uid;
    _signingOut = false;
    _lastConfiguration = null;
    _lastObservedConfiguration = null;
    preferences = const BackgroundMatchingPreferences();
    await _stopNative();
    if (uid == null) {
      status = 'Sign in to enable background matching.';
      notifyListeners();
      return;
    }
    final storage = await SharedPreferences.getInstance();
    if (generation != _generation ||
        FirebaseAuth.instance.currentUser?.uid != uid)
      return;
    _deviceId = storage.getString('prox_background_device_id') ?? '';
    if (_deviceId.isEmpty) {
      final random = Random.secure();
      _deviceId = List.generate(
        24,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await storage.setString('prox_background_device_id', _deviceId);
    }
    if (generation != _generation ||
        FirebaseAuth.instance.currentUser?.uid != uid)
      return;
    try {
      final raw = storage.getString('prox_background_matching_$uid');
      if (raw != null)
        preferences = BackgroundMatchingPreferences.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
    } catch (_) {}
    _changed();
  }

  void _changed() {
    if (!supported) return;
    final settings = UserSettingsService.instance.current;
    final observed = jsonEncode([
      _uid,
      _deviceId,
      _signingOut,
      preferences.toJson(),
      LocationPrivacyService.instance.locationEnabled,
      settings.matchDiscovery.toJson(),
      settings.matchNotificationsEnabled,
      settings.matchSoundEnabled,
      settings.rareMatchSoundEnabled,
      DateTime.now().timeZoneOffset.inMinutes,
    ]);
    // Server echoes can emit unchanged settings. Never turn those emissions
    // into another write, even after a rejected configuration attempt.
    if (observed == _lastObservedConfiguration) return;
    _lastObservedConfiguration = observed;
    final generation = _generation;
    final revision = ++_configurationRevision;
    // Shut down the native collector before awaiting any network operation.
    if (_signingOut ||
        !preferences.enabled ||
        !LocationPrivacyService.instance.locationEnabled ||
        UserSettingsService.instance.current.matchDiscovery.modeKind ==
            MatchingModeKind.off) {
      _lastConfiguration = null;
      unawaited(_stopNative());
      unawaited(_disableServer());
    }
    if (_signingOut) return;
    MatchingModeService.instance.syncSessionToServer();
    _queue = _queue
        .catchError((Object _) {})
        .then((_) => _sync(generation, revision))
        .catchError((Object _) {
          status =
              'Background matching could not start. Check location permissions and reopen Prox.';
          notifyListeners();
        });
  }

  Future<void> _stopNative() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('configure', {
        'enabled': false,
        'uid': _uid ?? '',
        'deviceId': _deviceId,
      });
    } catch (_) {}
  }

  Future<void> _sync(int generation, int revision) async {
    final uid = _uid;
    if (uid == null ||
        generation != _generation ||
        revision != _configurationRevision ||
        _signingOut ||
        FirebaseAuth.instance.currentUser?.uid != uid)
      return;
    final granted = await Permission.locationAlways.isGranted;
    if (generation != _generation ||
        revision != _configurationRevision ||
        _signingOut)
      return;
    final settings = UserSettingsService.instance.current;
    final discovery = settings.matchDiscovery;
    final enabled =
        preferences.enabled &&
        granted &&
        LocationPrivacyService.instance.locationEnabled &&
        discovery.modeKind != MatchingModeKind.off;
    final payload = {
      ...preferences.toJson(),
      'enabled': enabled,
      'deviceId': _deviceId,
      'notificationsEnabled': settings.matchNotificationsEnabled,
      'soundEnabled':
          settings.matchSoundEnabled && settings.rareMatchSoundEnabled,
      'utcOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
    };
    final configuration = jsonEncode([payload, discovery.toJson()]);
    if (configuration == _lastConfiguration) return;
    try {
      if (!enabled) await _stopNative();
      final batch = FirebaseFirestore.instance.batch();
      batch.set(
        FirebaseFirestore.instance.doc(
          'users/$uid/settings/backgroundMatching',
        ),
        payload,
        SetOptions(merge: true),
      );
      if (!enabled)
        batch.delete(
          FirebaseFirestore.instance.doc(
            'users/$uid/backgroundPresence/current',
          ),
        );
      await batch.commit().timeout(const Duration(seconds: 8));
      if (generation != _generation ||
          revision != _configurationRevision ||
          _signingOut ||
          FirebaseAuth.instance.currentUser?.uid != uid)
        return;
      final running =
          enabled &&
          await _channel.invokeMethod<bool>('configure', {
                'uid': uid,
                'deviceId': _deviceId,
                'enabled': true,
                'mode': discovery.modeKind.name,
              }) ==
              true;
      _lastConfiguration = configuration;
      status = !preferences.enabled
          ? 'Background matching is off.'
          : !granted
          ? 'Allow location all the time in phone settings to continue.'
          : !enabled
          ? 'Paused while location or matching is off.'
          : running
          ? 'Looking quietly for connections, including while Prox is closed.'
          : 'Background matching could not start. Reopen Prox and check phone permissions.';
    } catch (_) {
      status =
          'Could not sync background matching. Check your connection and reopen this screen.';
    }
    notifyListeners();
  }

  Future<void> update(BackgroundMatchingPreferences next) async {
    if (!supported || _uid == null) return;
    busy = true;
    notifyListeners();
    final uid = _uid!;
    try {
      final storage = await SharedPreferences.getInstance();
      if (_uid != uid) return;
      preferences = next;
      await storage.setString(
        'prox_background_matching_$uid',
        jsonEncode(next.toJson()),
      );
      _lastConfiguration = null;
      _changed();
      await _queue;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> requestLocationAccess() async {
    if (!supported) return false;
    if (!await Permission.locationWhenInUse.isGranted &&
        !await Permission.locationWhenInUse.request().isGranted)
      return false;
    return Permission.locationAlways.request().isGranted;
  }

  Future<void> _disableServer() async {
    final uid = _uid;
    if (uid == null || FirebaseAuth.instance.currentUser?.uid != uid) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.set(
        FirebaseFirestore.instance.doc(
          'users/$uid/settings/backgroundMatching',
        ),
        {'enabled': false},
        SetOptions(merge: true),
      );
      batch.delete(
        FirebaseFirestore.instance.doc('users/$uid/backgroundPresence/current'),
      );
      await batch.commit().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> stopForSignOut() async {
    if (!supported) return;
    _signingOut = true;
    _generation++;
    _configurationRevision++;
    await _stopNative();
    await _disableServer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lastConfiguration = null;
      _lastObservedConfiguration = null;
      _changed();
    }
  }

  @override
  void dispose() {
    _auth?.cancel();
    _settings?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    LocationPrivacyService.instance.removeListener(_changed);
    super.dispose();
  }
}
