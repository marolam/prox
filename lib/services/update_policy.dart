/// Validated app version. Numeric build numbers are compared only when both
/// sides specify one; a release tag without a build does not imply build zero.
class AppUpdateVersion implements Comparable<AppUpdateVersion> {
  const AppUpdateVersion._(this.core, this.prerelease, this.build);

  final List<int> core;
  final List<String> prerelease;
  final int? build;

  static AppUpdateVersion? tryParse(String input) {
    final match = RegExp(
      r'^[vV]?(0|[1-9]\d*)\.(0|[1-9]\d*)(?:\.(0|[1-9]\d*))?'
      r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
      r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
    ).firstMatch(input.trim());
    if (match == null) return null;
    final core = [
      int.tryParse(match[1]!),
      int.tryParse(match[2]!),
      int.tryParse(match[3] ?? '0'),
    ];
    if (core.any((part) => part == null)) return null;
    final prerelease = match[4]?.split('.') ?? const <String>[];
    if (prerelease.any((part) =>
        RegExp(r'^\d+$').hasMatch(part) &&
        part.length > 1 &&
        part.startsWith('0'))) return null;
    return AppUpdateVersion._(
      core.cast<int>(),
      prerelease,
      int.tryParse(match[5] ?? ''),
    );
  }

  @override
  int compareTo(AppUpdateVersion other) {
    for (var i = 0; i < core.length; i++) {
      final comparison = core[i].compareTo(other.core[i]);
      if (comparison != 0) return comparison;
    }
    if (prerelease.isEmpty != other.prerelease.isEmpty) {
      return prerelease.isEmpty ? 1 : -1;
    }
    final length = prerelease.length < other.prerelease.length
        ? prerelease.length
        : other.prerelease.length;
    for (var i = 0; i < length; i++) {
      final left = prerelease[i];
      final right = other.prerelease[i];
      final leftNumeric = RegExp(r'^\d+$').hasMatch(left);
      final rightNumeric = RegExp(r'^\d+$').hasMatch(right);
      final comparison = leftNumeric && rightNumeric
          ? (left.length == right.length
              ? left.compareTo(right)
              : left.length.compareTo(right.length))
          : (leftNumeric != rightNumeric
              ? (leftNumeric ? -1 : 1)
              : left.compareTo(right));
      if (comparison != 0) return comparison;
    }
    final prereleaseLength =
        prerelease.length.compareTo(other.prerelease.length);
    if (prereleaseLength != 0) return prereleaseLength;
    return build != null && other.build != null
        ? build!.compareTo(other.build!)
        : 0;
  }
}

class LoginUpdateCheckResult {
  const LoginUpdateCheckResult({
    required this.updateAvailable,
    required this.mustUpdateNow,
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.importantRequired,
    required this.importantMinVersion,
    required this.minimumRequiredVersion,
    required this.minimumRequired,
    required this.minimumRequiredNotes,
    required this.pollMinutes,
    this.checkFailed = false,
  });

  final bool updateAvailable;
  final bool mustUpdateNow;
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final bool importantRequired;
  final String importantMinVersion;
  final bool minimumRequired;
  final String minimumRequiredVersion;
  final String minimumRequiredNotes;
  final int pollMinutes;
  final bool checkFailed;
}

/// The same policy is used on both platforms. Platform-specific version keys
/// allow store review to finish before requiring a version on that platform.
class UpdatePolicy {
  static bool isSafeUpdateUrl(String value, {required bool isIos}) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.isScheme('https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) return false;
    final path = uri.path.toLowerCase();
    if (!isIos) return true;
    if (path.endsWith('.apk') || path.endsWith('.ipa')) return false;
    final host = uri.host.toLowerCase();
    if (host == 'apps.apple.com' || host == 'testflight.apple.com') {
      return true;
    }
    final isTesterPortalHost = host == 'prox-us.com' || host == 'www.prox-us.com';
    final isTesterPortalPath = path.endsWith('/tester-portal.html');
    return isTesterPortalHost && isTesterPortalPath;
  }

  static LoginUpdateCheckResult evaluate({
    required String currentVersion,
    required Map<String, Object> config,
    required bool isIos,
    required bool isProduction,
    required String fallbackDownloadUrl,
    String buildMinimumVersion = '',
    String buildMinimumNotes = '',
    bool checkFailed = false,
  }) {
    String readString(String key) => (config[key] ?? '').toString().trim();
    bool readBool(String key, bool fallback) {
      final value =
          config['${key}_${isIos ? 'ios' : 'android'}'] ?? config[key];
      if (value == null) return fallback;
      return value == true || value.toString().toLowerCase() == 'true';
    }

    String platformVersion(String key) {
      final override = readString('${key}_${isIos ? 'ios' : 'android'}');
      return override.isNotEmpty ? override : readString(key);
    }

    final enabled = readBool('update_check_enabled', true);
    final current = AppUpdateVersion.tryParse(currentVersion);
    bool below(String target) {
      final parsed = AppUpdateVersion.tryParse(target);
      return current != null && parsed != null && current.compareTo(parsed) < 0;
    }

    final latestRaw = platformVersion('update_latest_version');
    final latest = AppUpdateVersion.tryParse(latestRaw) != null
        ? latestRaw
        : currentVersion;
    final remoteMinimum = platformVersion('update_minimum_required_version');
    final buildMinimumValid =
        AppUpdateVersion.tryParse(buildMinimumVersion) != null;
    final buildRequired = buildMinimumValid && below(buildMinimumVersion);
    final remoteRequired = enabled &&
        readBool('update_minimum_required_enabled', true) &&
        below(remoteMinimum);
    final minimumRequired = buildRequired || remoteRequired;
    final minimumVersion = buildRequired &&
            (!remoteRequired ||
                AppUpdateVersion.tryParse(buildMinimumVersion)!
                        .compareTo(AppUpdateVersion.tryParse(remoteMinimum)!) >=
                    0)
        ? buildMinimumVersion
        : (AppUpdateVersion.tryParse(remoteMinimum) != null
            ? remoteMinimum
            : '');
    final importantMinimum = platformVersion('update_important_min_version');
    final updateAvailable = enabled && below(latest);
    final rawUrl =
        readString(isIos ? 'update_download_url_ios' : 'update_download_url');
    final downloadUrl =
        isSafeUpdateUrl(rawUrl, isIos: isIos) ? rawUrl : fallbackDownloadUrl;
    final poll = int.tryParse(readString('update_poll_minutes')) ?? 20;

    return LoginUpdateCheckResult(
      updateAvailable: updateAvailable || minimumRequired,
      mustUpdateNow: minimumRequired ||
          (isProduction &&
              enabled &&
              readBool('update_force_latest_enabled', true) &&
              below(latest)),
      currentVersion: currentVersion,
      latestVersion: minimumRequired &&
              below(minimumVersion) &&
              (AppUpdateVersion.tryParse(latest) == null ||
                  AppUpdateVersion.tryParse(minimumVersion)!
                          .compareTo(AppUpdateVersion.tryParse(latest)!) >
                      0)
          ? minimumVersion
          : latest,
      downloadUrl: downloadUrl,
      importantRequired: enabled &&
          readBool('update_important_enabled', false) &&
          below(importantMinimum),
      importantMinVersion: importantMinimum,
      minimumRequired: minimumRequired,
      minimumRequiredVersion: minimumVersion,
      minimumRequiredNotes: buildRequired
          ? buildMinimumNotes
          : readString('update_minimum_required_notes'),
      pollMinutes: poll.clamp(5, 240),
      checkFailed: checkFailed ||
          current == null ||
          (enabled && latestRaw.isEmpty) ||
          (latestRaw.isNotEmpty &&
              AppUpdateVersion.tryParse(latestRaw) == null),
    );
  }
}
