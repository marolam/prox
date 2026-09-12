import 'dart:async';
import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/login_update_check_service.dart';
import 'package:prox/services/update_policy.dart';

void main() {
  LoginUpdateCheckResult evaluate(
    Map<String, Object> config, {
    bool isIos = false,
    bool isProduction = true,
    String current = '0.18.8+18',
    String buildMinimum = '',
  }) => UpdatePolicy.evaluate(
    currentVersion: current,
    config: config,
    isIos: isIos,
    isProduction: isProduction,
    fallbackDownloadUrl: 'https://www.prox-us.com/tester-portal.html',
    buildMinimumVersion: buildMinimum,
  );

  test('malformed policy cannot lock everyone out', () {
    for (final invalid in [
      'release-2026',
      '0.18.8+18+19',
      '01.2.3',
      '1.0.0-01',
      'unknown',
      '1.2oops',
    ]) {
      expect(AppUpdateVersion.tryParse(invalid), isNull, reason: invalid);
      final result = evaluate({
        'update_latest_version': invalid,
        'update_minimum_required_version': invalid,
        'update_important_min_version': invalid,
        'update_important_enabled': true,
      });
      expect(result.mustUpdateNow, isFalse, reason: invalid);
      expect(result.importantRequired, isFalse);
      expect(result.checkFailed, isTrue);
    }
  });

  test('prerelease precedence and numeric build ordering', () {
    final versions = [
      '1.0.0-alpha',
      '1.0.0-alpha.2',
      '1.0.0-alpha.11',
      '1.0.0-beta',
      '1.0.0-rc.1',
      '1.0.0',
      '1.0.0+2',
      '1.0.0+3',
      '1.1',
    ];
    for (var i = 0; i < versions.length - 1; i++) {
      final compared = AppUpdateVersion.tryParse(
        versions[i],
      )!.compareTo(AppUpdateVersion.tryParse(versions[i + 1])!);
      expect(compared, i == 5 ? 0 : lessThan(0));
    }
    expect(
      AppUpdateVersion.tryParse(
        '1.0.0+3',
      )!.compareTo(AppUpdateVersion.tryParse('v1.0')!),
      0,
    );
  });

  for (final isIos in [false, true]) {
    test('same mandatory shared policy on ${isIos ? "iOS" : "Android"}', () {
      expect(
        evaluate({
          'update_latest_version': '0.18.8+19',
        }, isIos: isIos).mustUpdateNow,
        isTrue,
      );
      expect(
        evaluate({
          'update_latest_version': '0.18.8+18',
        }, isIos: isIos).mustUpdateNow,
        isFalse,
      );
      expect(
        evaluate({
          'update_latest_version': '0.18.8+17',
        }, isIos: isIos).mustUpdateNow,
        isFalse,
      );
    });
  }

  test('platform override prevents locking iOS before review completes', () {
    final policy = <String, Object>{
      'update_latest_version': '0.19.0+20',
      'update_latest_version_ios': '0.18.8+18',
      'update_minimum_required_version': '0.19.0+20',
      'update_minimum_required_version_ios': '0.18.8+18',
    };
    expect(evaluate(policy).mustUpdateNow, isTrue);
    expect(evaluate(policy, isIos: true).mustUpdateNow, isFalse);
  });

  test(
    'kill switch disables remote gates but honors an explicit build floor',
    () {
      final policy = <String, Object>{
        'update_check_enabled': false,
        'update_latest_version': '99.0.0',
        'update_minimum_required_version': '99.0.0',
        'update_important_enabled': true,
        'update_important_min_version': '99.0.0',
      };
      expect(evaluate(policy).mustUpdateNow, isFalse);
      expect(evaluate(policy).importantRequired, isFalse);
      expect(evaluate(policy, buildMinimum: '0.19.0').mustUpdateNow, isTrue);
    },
  );

  test('tester latest is optional; explicit minimum is required', () {
    expect(
      evaluate({
        'update_latest_version': '0.19.0',
      }, isProduction: false).mustUpdateNow,
      isFalse,
    );
    expect(
      evaluate({
        'update_minimum_required_version': '0.19.0',
      }, isProduction: false).mustUpdateNow,
      isTrue,
    );
  });

  test('iOS never inherits an Android link or a raw un-installable binary', () {
    final android = evaluate({
      'update_download_url': 'https://example.com/update.apk',
    });
    expect(android.downloadUrl, 'https://example.com/update.apk');
    for (final url in [
      'https://example.com/update.apk',
      'https://example.com/update.ipa',
      'https://github.com/marolam/prox/releases/latest/download/app-release.apk',
      'https://example.com/update',
      'javascript:alert(1)',
      'http://example.com/update',
      'https://user:password@example.com',
    ]) {
      final ios = evaluate({
        'update_download_url': url,
        'update_download_url_ios': url,
      }, isIos: true);
      expect(ios.downloadUrl, 'https://www.prox-us.com/tester-portal.html');
    }
    expect(
      evaluate({
        'update_download_url_ios': 'https://testflight.apple.com/join/abc',
      }, isIos: true).downloadUrl,
      'https://testflight.apple.com/join/abc',
    );
  });

  test(
    'unknown installed version reports a failed check without inventing a gate',
    () {
      final result = evaluate({
        'update_latest_version': '0.19.0',
      }, current: 'unknown');
      expect(result.checkFailed, isTrue);
      expect(result.mustUpdateNow, isFalse);
    },
  );

  test(
    'simultaneous update checks share one fetch and reuse a recent result',
    () async {
      final pending = Completer<UpdateConfigSnapshot>();
      var fetches = 0;
      final service = LoginUpdateCheckService.forTesting(
        versionLoader: () async => '0.18.8+18',
        configLoader: (_) {
          fetches++;
          return pending.future;
        },
      );
      final first = service.check(forceRefresh: true);
      final second = service.check(forceRefresh: true);
      expect(identical(first, second), isTrue);
      pending.complete(
        const UpdateConfigSnapshot({'update_latest_version': '0.19.0'}),
      );
      expect((await first).mustUpdateNow, isTrue);
      expect(await service.check(), same(await second));
      expect(fetches, 1);
      service.latestResult.dispose();
    },
  );

  test(
    'cold offline startup still enforces the previously activated policy',
    () async {
      final service = LoginUpdateCheckService.forTesting(
        versionLoader: () async => '0.18.8+18',
        configLoader: (_) async => const UpdateConfigSnapshot({
          'update_latest_version': '0.19.0',
          'update_minimum_required_version': '0.19.0',
        }, fetchFailed: true),
      );
      final result = await service.check(forceRefresh: true);
      expect(result.checkFailed, isTrue);
      expect(result.mustUpdateNow, isTrue);
      service.latestResult.dispose();
    },
  );

  test(
    'failed Firebase fetch still reads activated native values on cold startup',
    () async {
      final nativeConfig = _OfflineRemoteConfig();
      final service = LoginUpdateCheckService.forTesting(
        versionLoader: () async => '0.18.8+18',
        remoteConfig: nativeConfig,
      );
      final result = await service.check(forceRefresh: true);
      expect(nativeConfig.fetchAttempts, 1);
      expect(nativeConfig.activatedReads, 1);
      expect(result.mustUpdateNow, isTrue);
      expect(result.minimumRequiredVersion, '0.19.0+19');
      expect(result.checkFailed, isTrue);
      service.latestResult.dispose();
    },
  );
}

class _OfflineRemoteConfig extends Fake implements FirebaseRemoteConfig {
  int fetchAttempts = 0;
  int activatedReads = 0;
  @override
  Future<void> ensureInitialized() async {}
  @override
  Future<void> setDefaults(Map<String, dynamic> defaults) async {}
  @override
  Future<void> setConfigSettings(RemoteConfigSettings settings) async {}
  @override
  Future<bool> fetchAndActivate() async {
    fetchAttempts++;
    throw StateError('device offline');
  }

  @override
  Map<String, RemoteConfigValue> getAll() {
    activatedReads++;
    return {
      for (final key in [
        'update_latest_version',
        'update_minimum_required_version',
      ])
        key: RemoteConfigValue(
          utf8.encode('0.19.0+19'),
          ValueSource.valueRemote,
        ),
    };
  }
}
