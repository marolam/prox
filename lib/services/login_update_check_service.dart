import "dart:async";
import "dart:convert";

import "package:firebase_remote_config/firebase_remote_config.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:http/http.dart" as http;
import "package:url_launcher/url_launcher_string.dart";

import "package:prox/screens/services/build_info_service.dart";
import "package:prox/services/app_build_info_service.dart";

class LoginUpdateCheckResult {
  const LoginUpdateCheckResult({
    required this.updateAvailable,
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.importantRequired,
    required this.importantMinVersion,
    required this.pollMinutes,
  });

  final bool updateAvailable;
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final bool importantRequired;
  final String importantMinVersion;
  final int pollMinutes;
}

class LoginUpdateCheckService with WidgetsBindingObserver {
  LoginUpdateCheckService._();

  static final LoginUpdateCheckService instance = LoginUpdateCheckService._();

  static const String _enabledKey = "update_check_enabled";
  static const String _latestVersionKey = "update_latest_version";
  static const String _downloadUrlKey = "update_download_url";
  static const String _importantEnabledKey = "update_important_enabled";
  static const String _importantMinVersionKey = "update_important_min_version";
  static const String _pollMinutesKey = "update_poll_minutes";

  static const String _defaultDownloadUrl =
      "https://github.com/marolam/prox/releases/latest/download/app-release.apk";
  static const String _testerPortalUrl =
      "https://www.prox-us.com/tester-portal.html";
  static const String _testerIndexUrl =
      "https://www.prox-us.com/testers.html";
  static const String _configuredPublicApkUrl =
      String.fromEnvironment("PROX_PUBLIC_APK_URL", defaultValue: "");
  static const String _latestReleasePageUrl =
      "https://github.com/marolam/prox/releases/latest";
  static const String _latestReleaseApiUrl =
      "https://api.github.com/repos/marolam/prox/releases/latest";
  static const int _defaultPollMinutes = 20;

  GlobalKey<NavigatorState>? _navigatorKey;
  Timer? _liveTimer;
  bool _liveWatcherStarted = false;
  bool _liveCheckInFlight = false;
  DateTime? _lastImportantPromptAt;
  String _lastPromptedUpdateVersion = "";

  void registerNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  void startLiveWatcher() {
    if (_liveWatcherStarted) return;
    _liveWatcherStarted = true;
    WidgetsBinding.instance.addObserver(this);
    _scheduleLiveTimer(minutes: _defaultPollMinutes);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(seconds: 2), () async {
        await _runLiveCheck(forceRefresh: true);
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Fetch fresh values on resume so long-running sessions can see urgent updates quickly.
      // ignore: discarded_futures
      _runLiveCheck(forceRefresh: true);
    }
  }

  Future<LoginUpdateCheckResult> check({bool forceRefresh = false}) async {
    final appVersion = (await AppBuildInfoService.instance.fullVersion()).trim();
    final fallbackVersion = BuildInfoService.instance.info.version.trim();
    final currentVersion =
        appVersion.isNotEmpty && appVersion != "unknown" ? appVersion : fallbackVersion;

    if (kIsWeb) {
      return LoginUpdateCheckResult(
        updateAvailable: false,
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        downloadUrl: _defaultDownloadUrl,
        importantRequired: false,
        importantMinVersion: "",
        pollMinutes: _defaultPollMinutes,
      );
    }

    String latestVersion = currentVersion;
    String downloadUrl = _defaultDownloadUrl;
    bool enabled = true;
    bool importantEnabled = false;
    String importantMinVersion = "";
    int pollMinutes = _defaultPollMinutes;

    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 4),
          minimumFetchInterval: forceRefresh
              ? Duration.zero
              : (kReleaseMode
                    ? const Duration(minutes: 15)
                    : const Duration(seconds: 20)),
        ),
      );
      await rc.setDefaults(<String, Object>{
        _enabledKey: true,
        _latestVersionKey: currentVersion,
        _downloadUrlKey: _defaultDownloadUrl,
        _importantEnabledKey: false,
        _importantMinVersionKey: "",
        _pollMinutesKey: _defaultPollMinutes,
      });
      await rc.fetchAndActivate();

      enabled = rc.getBool(_enabledKey);
      latestVersion = rc.getString(_latestVersionKey).trim();
      downloadUrl = rc.getString(_downloadUrlKey).trim();
      importantEnabled = rc.getBool(_importantEnabledKey);
      importantMinVersion = rc.getString(_importantMinVersionKey).trim();
      pollMinutes = rc.getInt(_pollMinutesKey).clamp(5, 240);
      if (latestVersion.isEmpty) latestVersion = currentVersion;
      if (downloadUrl.isEmpty) downloadUrl = _defaultDownloadUrl;
    } catch (e) {
      debugPrint("[UpdateCheck] Remote Config unavailable: $e");
    }

    try {
      final gh = await _fetchLatestFromGitHub();
      if (gh != null) {
        // Never let a fallback source reduce the currently known latest version.
        // Keep the greater semantic version between RC and GitHub values.
        if (gh.version.isNotEmpty &&
            _compareVersions(gh.version, latestVersion) > 0) {
          latestVersion = gh.version;
        }
        if (gh.downloadUrl.isNotEmpty &&
            _compareVersions(gh.version, latestVersion) >= 0) {
          downloadUrl = gh.downloadUrl;
        }
      }
    } catch (e) {
      debugPrint("[UpdateCheck] GitHub latest lookup failed: $e");
    }

    final updateAvailable =
        enabled && _compareVersions(latestVersion, currentVersion) > 0;
    final importantRequired = importantEnabled &&
        importantMinVersion.isNotEmpty &&
        _compareVersions(currentVersion, importantMinVersion) < 0;

    return LoginUpdateCheckResult(
      updateAvailable: updateAvailable,
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      downloadUrl: downloadUrl,
      importantRequired: importantRequired,
      importantMinVersion: importantMinVersion,
      pollMinutes: pollMinutes,
    );
  }

  Future<void> checkAndNotify(
    BuildContext context, {
    bool forceRefresh = false,
    bool showUpToDateSnackBar = true,
  }) async {
    final result = await check(forceRefresh: forceRefresh);
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    if (result.updateAvailable) {
      _showUpdateSnackBar(context, result, throttleByVersion: !showUpToDateSnackBar);
      return;
    }

    if (!showUpToDateSnackBar) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text("You're up to date (v${result.currentVersion})."),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: "Open latest",
          onPressed: () {
            // ignore: discarded_futures
            openLatestUpdate(context, preferredUrl: result.downloadUrl);
          },
        ),
      ),
    );
  }

  Future<bool> openLatestUpdate(
    BuildContext context, {
    String? preferredUrl,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final candidates = <String>[
      (preferredUrl ?? "").trim(),
      _configuredPublicApkUrl.trim(),
      _defaultDownloadUrl,
      _testerPortalUrl,
      _testerIndexUrl,
      _latestReleasePageUrl,
    ].where((u) => u.isNotEmpty).toList();

    final String resolved = await _resolveReachableUpdateUrl(candidates);

    final bool launchedResolved = await launchUrlString(
      resolved,
      mode: LaunchMode.externalApplication,
    );
    if (launchedResolved) return true;

    // Last attempt: open release page even if reachability checks failed.
    final bool launchedFallback = await launchUrlString(
      _latestReleasePageUrl,
      mode: LaunchMode.externalApplication,
    );
    if (launchedFallback) return true;

    messenger?.showSnackBar(
      const SnackBar(
        content: Text("Couldn't open update link right now."),
        duration: Duration(seconds: 4),
      ),
    );
    return false;
  }

  Future<String> _resolveReachableUpdateUrl(List<String> candidates) async {
    for (final raw in candidates) {
      final url = raw.trim();
      if (url.isEmpty) continue;
      if (await _looksReachable(url)) {
        return url;
      }
    }
    return candidates.firstWhere((u) => u.trim().isNotEmpty,
        orElse: () => _latestReleasePageUrl);
  }

  Future<bool> _looksReachable(String rawUrl) async {
    Uri uri;
    try {
      uri = Uri.parse(rawUrl);
    } catch (_) {
      return false;
    }
    if (!(uri.isScheme("http") || uri.isScheme("https"))) {
      return false;
    }

    try {
      final res = await http.head(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode >= 200 && res.statusCode < 400) return true;
      if (res.statusCode == 405 || res.statusCode == 501) {
        final getRes = await http.get(uri).timeout(const Duration(seconds: 4));
        return getRes.statusCode >= 200 && getRes.statusCode < 400;
      }
      return false;
    } catch (_) {
      try {
        final getRes = await http.get(uri).timeout(const Duration(seconds: 4));
        return getRes.statusCode >= 200 && getRes.statusCode < 400;
      } catch (_) {
        return false;
      }
    }
  }

  Future<void> checkAndPromptImportant(
    BuildContext context, {
    bool forceRefresh = false,
  }) async {
    final result = await check(forceRefresh: forceRefresh);
    if (!context.mounted) return;
    if (!result.importantRequired) return;

    final now = DateTime.now();
    if (_lastImportantPromptAt != null &&
        now.difference(_lastImportantPromptAt!) < const Duration(minutes: 20)) {
      return;
    }
    _lastImportantPromptAt = now;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Important update available"),
          content: Text(
            "You are on v${result.currentVersion}. "
            "This update expects at least v${result.importantMinVersion}. "
            "Please update to continue with the latest fixes.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Later"),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await openLatestUpdate(context, preferredUrl: result.downloadUrl);
              },
              child: const Text("Update now"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runLiveCheck({required bool forceRefresh}) async {
    if (_liveCheckInFlight) return;
    _liveCheckInFlight = true;
    try {
      final nav = _navigatorKey?.currentState;
      final ctx = _navigatorKey?.currentContext;
      if (nav == null || ctx == null || !nav.mounted || !ctx.mounted) return;

      final result = await check(forceRefresh: forceRefresh);
      _scheduleLiveTimer(minutes: result.pollMinutes);
      if (!ctx.mounted) return;
      if (result.importantRequired) {
        await checkAndPromptImportant(ctx, forceRefresh: false);
      } else if (result.updateAvailable) {
        _showUpdateSnackBar(ctx, result, throttleByVersion: true);
      }
    } finally {
      _liveCheckInFlight = false;
    }
  }

  void _showUpdateSnackBar(
    BuildContext context,
    LoginUpdateCheckResult result, {
    required bool throttleByVersion,
  }) {
    if (throttleByVersion && _lastPromptedUpdateVersion == result.latestVersion) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    _lastPromptedUpdateVersion = result.latestVersion;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          "New update available (v${result.latestVersion}). You are on v${result.currentVersion}.",
        ),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: "Update",
          onPressed: () {
            // ignore: discarded_futures
            openLatestUpdate(context, preferredUrl: result.downloadUrl);
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
    _showUpdateSnackBar(
      context,
      result,
      throttleByVersion: throttleByVersion,
    );
  }

  @visibleForTesting
  void resetPromptThrottleForTest() {
    _lastPromptedUpdateVersion = "";
  }

  void _scheduleLiveTimer({required int minutes}) {
    _liveTimer?.cancel();
    final safeMinutes = minutes.clamp(5, 240);
    _liveTimer = Timer.periodic(Duration(minutes: safeMinutes), (_) {
      // ignore: discarded_futures
      _runLiveCheck(forceRefresh: true);
    });
  }

  int _compareVersions(String a, String b) {
    final aParts = _numericSegments(a);
    final bParts = _numericSegments(b);
    final maxLen = aParts.length > bParts.length ? aParts.length : bParts.length;
    for (int i = 0; i < maxLen; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  List<int> _numericSegments(String input) {
    final matches = RegExp(r"\d+").allMatches(input);
    final out = <int>[];
    for (final m in matches) {
      final v = int.tryParse(m.group(0) ?? "");
      if (v != null) out.add(v);
    }
    return out;
  }

  Future<({String version, String downloadUrl})?> _fetchLatestFromGitHub() async {
    final uri = Uri.parse(_latestReleaseApiUrl);
    final res = await http.get(
      uri,
      headers: <String, String>{"Accept": "application/vnd.github+json"},
    ).timeout(const Duration(seconds: 5));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      return null;
    }

    final dynamic parsed = jsonDecode(res.body);
    if (parsed is! Map<String, dynamic>) return null;

    String version = ((parsed["tag_name"] ?? "").toString()).trim();
    if (version.startsWith("v") || version.startsWith("V")) {
      version = version.substring(1);
    }

    String downloadUrl = _defaultDownloadUrl;
    final assets = parsed["assets"];
    if (assets is List) {
      for (final a in assets) {
        if (a is! Map) continue;
        final name = (a["name"] ?? "").toString().trim().toLowerCase();
        final url = (a["browser_download_url"] ?? "").toString().trim();
        if (name == "app-release.apk" && url.isNotEmpty) {
          downloadUrl = url;
          break;
        }
      }
    }

    return (version: version, downloadUrl: downloadUrl);
  }
}