import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:prox/services/app_build_info_service.dart';
import 'package:prox/services/update_policy.dart';

export 'package:prox/services/update_policy.dart' show LoginUpdateCheckResult;

class UpdateConfigSnapshot {
  const UpdateConfigSnapshot(this.values, {this.fetchFailed = false});
  final Map<String, Object> values;
  final bool fetchFailed;
}

class LoginUpdateCheckService with WidgetsBindingObserver {
  LoginUpdateCheckService._();

  @visibleForTesting
  LoginUpdateCheckService.forTesting({
    required Future<String> Function() versionLoader,
    Future<UpdateConfigSnapshot> Function(bool forceRefresh)? configLoader,
    FirebaseRemoteConfig? remoteConfig,
    bool isIos = false,
    bool isProduction = true,
  }) : _versionLoader = versionLoader,
       _configLoader = configLoader,
       _remoteConfig = remoteConfig,
       _isIosOverride = isIos,
       _isProductionOverride = isProduction;

  static final LoginUpdateCheckService instance = LoginUpdateCheckService._();
  static const String _defaultDownloadUrl =
      'https://github.com/marolam/prox/releases/latest/download/app-release.apk';
  static const String _iosUpdateUrlFromEnv = String.fromEnvironment(
    'PROX_IOS_UPDATE_URL',
  );
  static const String _testerPortalUrl =
      'https://www.prox-us.com/tester-portal.html';
  static const String _configuredPublicApkUrl = String.fromEnvironment(
    'PROX_PUBLIC_APK_URL',
  );
  static const bool _testerBuild = bool.fromEnvironment('PROX_TESTER_BUILD');
  static const String _minimumRequiredVersionFromEnv = String.fromEnvironment(
    'PROX_MIN_REQUIRED_VERSION',
  );
  static const String _minimumRequiredNotesFromEnv = String.fromEnvironment(
    'PROX_MIN_REQUIRED_NOTES',
    defaultValue:
        'Please update to continue with the latest matching and safety fixes.',
  );
  static const bool _enforceMinimumFromEnv = bool.fromEnvironment(
    'PROX_ENFORCE_MINIMUM_VERSION',
    defaultValue: true,
  );
  static const int _defaultPollMinutes = 20;

  Future<String> Function()? _versionLoader;
  Future<UpdateConfigSnapshot> Function(bool forceRefresh)? _configLoader;
  FirebaseRemoteConfig? _remoteConfig;
  bool? _isIosOverride;
  bool? _isProductionOverride;
  final ValueNotifier<LoginUpdateCheckResult?> latestResult = ValueNotifier(
    null,
  );
  Future<LoginUpdateCheckResult>? _checkInFlight;
  DateTime? _lastCheckAt;
  GlobalKey<NavigatorState>? _navigatorKey;
  Timer? _liveTimer;
  StreamSubscription<RemoteConfigUpdate>? _remoteUpdates;
  bool _liveWatcherStarted = false;
  bool _liveCheckInFlight = false;
  DateTime? _lastImportantPromptAt;
  String _lastPromptedUpdateVersion = '';

  bool get _isIos =>
      _isIosOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  void registerNavigatorKey(GlobalKey<NavigatorState> key) =>
      _navigatorKey = key;

  void startLiveWatcher() {
    if (_liveWatcherStarted || kIsWeb) return;
    _liveWatcherStarted = true;
    WidgetsBinding.instance.addObserver(this);
    _scheduleLiveTimer(minutes: _defaultPollMinutes);
    try {
      final rc = FirebaseRemoteConfig.instance;
      _remoteUpdates = rc.onConfigUpdated.listen(
        (event) async {
          if (!event.updatedKeys.any((key) => key.startsWith('update_')))
            return;
          try {
            await rc.activate();
            // Finish an older fetch before evaluating the newly activated policy.
            await _checkInFlight;
            _lastCheckAt = null;
            await check();
          } catch (error) {
            debugPrint('[UpdateCheck] Live config activation failed: $error');
          }
        },
        onError: (Object error) {
          debugPrint(
            '[UpdateCheck] Live config unavailable; polling continues: $error',
          );
        },
      );
    } catch (error) {
      debugPrint(
        '[UpdateCheck] Live config unavailable; polling continues: $error',
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_liveWatcherStarted) unawaited(_runLiveCheck(forceRefresh: false));
    });
  }

  void stopLiveWatcher() {
    _liveWatcherStarted = false;
    WidgetsBinding.instance.removeObserver(this);
    _liveTimer?.cancel();
    _liveTimer = null;
    unawaited(_remoteUpdates?.cancel());
    _remoteUpdates = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleLiveTimer(
        minutes: latestResult.value?.pollMinutes ?? _defaultPollMinutes,
      );
      unawaited(_runLiveCheck(forceRefresh: true));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _liveTimer?.cancel();
    }
  }

  /// Login, settings, lifecycle events and the gate share one in-flight request.
  Future<LoginUpdateCheckResult> check({bool forceRefresh = false}) {
    final pending = _checkInFlight;
    if (pending != null) return pending;
    final cached = latestResult.value;
    if (!forceRefresh &&
        cached != null &&
        _lastCheckAt != null &&
        DateTime.now().difference(_lastCheckAt!) <
            const Duration(seconds: 30)) {
      return Future.value(cached);
    }
    final request = _performCheck(forceRefresh: forceRefresh);
    _checkInFlight = request;
    return request;
  }

  Future<LoginUpdateCheckResult> _performCheck({
    required bool forceRefresh,
  }) async {
    try {
      final version =
          await (_versionLoader?.call() ??
              AppBuildInfoService.instance.fullVersion());
      final snapshot = kIsWeb
          ? const UpdateConfigSnapshot({'update_check_enabled': false})
          : await (_configLoader?.call(forceRefresh) ??
                _loadConfig(forceRefresh));
      final result = UpdatePolicy.evaluate(
        currentVersion: version.trim(),
        config: snapshot.values,
        isIos: _isIos,
        isProduction: _isProductionOverride ?? (kReleaseMode && !_testerBuild),
        fallbackDownloadUrl: _platformDefaultUpdateUrl(),
        buildMinimumVersion: !kIsWeb && _enforceMinimumFromEnv
            ? _minimumRequiredVersionFromEnv.trim()
            : '',
        buildMinimumNotes: _minimumRequiredNotesFromEnv,
        checkFailed: snapshot.fetchFailed,
      );
      _lastCheckAt = DateTime.now();
      latestResult.value = result;
      return result;
    } finally {
      _checkInFlight = null;
    }
  }

  Future<UpdateConfigSnapshot> _loadConfig(bool forceRefresh) async {
    FirebaseRemoteConfig? rc;
    bool fetchFailed = false;
    try {
      rc = _remoteConfig ?? FirebaseRemoteConfig.instance;
      await rc.ensureInitialized().timeout(const Duration(seconds: 4));
      await rc.setDefaults(const <String, Object>{
        'update_check_enabled': true,
        'update_force_latest_enabled': true,
        'update_minimum_required_enabled': true,
        'update_important_enabled': false,
        'update_poll_minutes': _defaultPollMinutes,
      });
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 4),
          minimumFetchInterval: forceRefresh
              ? const Duration(seconds: 30)
              : const Duration(minutes: 15),
        ),
      );
      await rc.fetchAndActivate().timeout(const Duration(seconds: 5));
    } catch (error) {
      // Activated values persist across launches. An offline fetch must never
      // discard a previously downloaded mandatory version policy.
      fetchFailed = true;
      debugPrint('[UpdateCheck] Using activated/default config: $error');
    }
    final values = <String, Object>{};
    if (rc != null) {
      for (final entry in rc.getAll().entries) {
        if (entry.key.startsWith('update_'))
          values[entry.key] = entry.value.asString();
      }
    }
    // Release tags are not package versions (the protected v1.0 rollback, for
    // example). Remote Config is the authoritative per-platform release policy.
    return UpdateConfigSnapshot(values, fetchFailed: fetchFailed);
  }

  @visibleForTesting
  bool shouldEnforceMandatoryUpdate({
    required bool forceLatestEnabled,
    required bool updateAvailable,
    bool? releaseMode,
    bool? testerBuild,
  }) =>
      (releaseMode ?? kReleaseMode) &&
      !(testerBuild ?? _testerBuild) &&
      forceLatestEnabled &&
      updateAvailable;

  Future<void> checkAndNotify(
    BuildContext context, {
    bool forceRefresh = false,
    bool showUpToDateSnackBar = true,
  }) async {
    final result = await check(forceRefresh: forceRefresh);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    if (result.updateAvailable) {
      _showUpdateSnackBar(
        context,
        result,
        throttleByVersion: !showUpToDateSnackBar,
      );
      return;
    }
    if (!showUpToDateSnackBar) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.checkFailed
              ? "Couldn't check for updates. Check your connection and try again."
              : "You're up to date (v${result.currentVersion}).",
        ),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: result.checkFailed ? 'Retry' : 'Open latest',
          onPressed: () {
            if (result.checkFailed) {
              unawaited(checkAndNotify(context, forceRefresh: true));
            } else {
              unawaited(
                openLatestUpdate(
                  context,
                  preferredUrl: result.downloadUrl,
                  targetVersion: result.latestVersion,
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Future<bool> openLatestUpdate(
    BuildContext context, {
    String? preferredUrl,
    String? targetVersion,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final resolvedPreferredUrl = _resolvePreferredUpdateUrl(
      preferredUrl,
      targetVersion: targetVersion,
    );
    final candidates = <String>{
      if (resolvedPreferredUrl.isNotEmpty) resolvedPreferredUrl,
      if (preferredUrl != null) preferredUrl.trim(),
      _platformDefaultUpdateUrl(),
      _testerPortalUrl,
    };
    for (final url in candidates) {
      if (!UpdatePolicy.isSafeUpdateUrl(url, isIos: _isIos)) continue;
      try {
        if (await launchUrlString(url, mode: LaunchMode.externalApplication))
          return true;
      } catch (error) {
        debugPrint('[UpdateCheck] Update link launch failed: $error');
      }
    }
    if (context.mounted) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text("Couldn't open the update link. Please try again."),
        ),
      );
    }
    return false;
  }

  String _resolvePreferredUpdateUrl(
    String? preferredUrl, {
    String? targetVersion,
  }) {
    final raw = preferredUrl?.trim() ?? '';
    if (raw.isEmpty || _isIos) return raw;

    final parsedVersion = AppUpdateVersion.tryParse((targetVersion ?? '').trim());
    if (parsedVersion == null) return raw;

    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.isScheme('https')) return raw;
    if (uri.host.toLowerCase() != 'github.com') return raw;

    final segments = uri.pathSegments;
    if (segments.length < 6) return raw;
    if (segments[2] != 'releases' ||
        segments[3] != 'latest' ||
        segments[4] != 'download') {
      return raw;
    }

    final version = (targetVersion ?? '').trim();
    final pinnedSegments = <String>[
      ...segments.take(3),
      'download',
      'v$version',
      ...segments.skip(5),
    ];
    return uri.replace(pathSegments: pinnedSegments).toString();
  }

  @visibleForTesting
  String resolvePreferredUpdateUrlForTest(
    String? preferredUrl, {
    String? targetVersion,
  }) =>
      _resolvePreferredUpdateUrl(preferredUrl, targetVersion: targetVersion);

  String _platformDefaultUpdateUrl() {
    final configured = _isIos ? _iosUpdateUrlFromEnv : _configuredPublicApkUrl;
    if (UpdatePolicy.isSafeUpdateUrl(configured, isIos: _isIos))
      return configured.trim();
    return _isIos ? _testerPortalUrl : _defaultDownloadUrl;
  }

  Future<void> checkAndPromptImportant(
    BuildContext context, {
    bool forceRefresh = false,
  }) async {
    final result = await check(forceRefresh: forceRefresh);
    if (context.mounted) await _promptImportant(context, result);
  }

  Future<void> _promptImportant(
    BuildContext context,
    LoginUpdateCheckResult result,
  ) async {
    if (!result.importantRequired || result.mustUpdateNow) return;
    final now = DateTime.now();
    if (_lastImportantPromptAt != null &&
        now.difference(_lastImportantPromptAt!) < const Duration(minutes: 20))
      return;
    _lastImportantPromptAt = now;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Important update available'),
        content: Text(
          'You are on v${result.currentVersion}. '
          'Please update to v${result.importantMinVersion} or newer for the latest fixes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(
                openLatestUpdate(
                  context,
                  preferredUrl: result.downloadUrl,
                  targetVersion: result.latestVersion,
                ),
              );
            },
            child: const Text('Update now'),
          ),
        ],
      ),
    );
  }

  Future<void> _runLiveCheck({required bool forceRefresh}) async {
    if (_liveCheckInFlight) return;
    _liveCheckInFlight = true;
    try {
      final result = await check(forceRefresh: forceRefresh);
      if (!_liveWatcherStarted) return;
      _scheduleLiveTimer(minutes: result.pollMinutes);
      final context = _navigatorKey?.currentState?.overlay?.context;
      if (context == null || !context.mounted || result.mustUpdateNow) return;
      if (result.importantRequired) {
        await _promptImportant(context, result);
      } else if (result.updateAvailable) {
        _showUpdateSnackBar(context, result, throttleByVersion: true);
      }
    } catch (error) {
      debugPrint('[UpdateCheck] Live check failed: $error');
    } finally {
      _liveCheckInFlight = false;
    }
  }

  void _showUpdateSnackBar(
    BuildContext context,
    LoginUpdateCheckResult result, {
    required bool throttleByVersion,
  }) {
    if (throttleByVersion && _lastPromptedUpdateVersion == result.latestVersion)
      return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    _lastPromptedUpdateVersion = result.latestVersion;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'New update available (v${result.latestVersion}). You are on v${result.currentVersion}.',
        ),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Update',
          onPressed: () {
            unawaited(
              openLatestUpdate(
                context,
                preferredUrl: result.downloadUrl,
                targetVersion: result.latestVersion,
              ),
            );
          },
        ),
      ),
    );
  }

  @visibleForTesting
  void showUpdatePromptForTest(
    BuildContext context,
    LoginUpdateCheckResult result, {
    bool throttleByVersion = false,
  }) {
    _showUpdateSnackBar(context, result, throttleByVersion: throttleByVersion);
  }

  @visibleForTesting
  void resetPromptThrottleForTest() => _lastPromptedUpdateVersion = '';

  void _scheduleLiveTimer({required int minutes}) {
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(Duration(minutes: minutes.clamp(5, 240)), (_) {
      unawaited(_runLiveCheck(forceRefresh: false));
    });
  }

  int compareVersions(String a, String b) {
    final left = AppUpdateVersion.tryParse(a);
    final right = AppUpdateVersion.tryParse(b);
    return left != null && right != null ? left.compareTo(right) : 0;
  }
}
