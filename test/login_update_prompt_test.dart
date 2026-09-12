import 'dart:async';

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:prox/services/login_update_check_service.dart";
import "package:prox/widgets/update_enforcement_gate.dart";

LoginUpdateCheckResult _updateResult({
  required String currentVersion,
  required String latestVersion,
}) {
  return LoginUpdateCheckResult(
    updateAvailable: true,
    mustUpdateNow: false,
    currentVersion: currentVersion,
    latestVersion: latestVersion,
    downloadUrl:
        "https://github.com/marolam/prox/releases/latest/download/app-release.apk",
    importantRequired: false,
    importantMinVersion: "",
    minimumRequiredVersion: "",
    minimumRequired: false,
    minimumRequiredNotes: "",
    pollMinutes: 20,
  );
}

void main() {
  test("version comparison does not invent a missing build number", () {
    final service = LoginUpdateCheckService.instance;

    expect(service.compareVersions("0.18.0+10", "0.18.0"), 0);
    expect(service.compareVersions("v0.18.0", "0.18.0+10"), 0);
    expect(service.compareVersions("0.18.0+11", "0.18.0+10"), greaterThan(0));
    expect(service.compareVersions("0.19.0", "0.18.0+99"), greaterThan(0));
  });

  test("mandatory update gate only blocks production release builds", () {
    final service = LoginUpdateCheckService.instance;

    expect(
      service.shouldEnforceMandatoryUpdate(
        forceLatestEnabled: true,
        updateAvailable: true,
        releaseMode: true,
        testerBuild: false,
      ),
      isTrue,
    );
    expect(
      service.shouldEnforceMandatoryUpdate(
        forceLatestEnabled: true,
        updateAvailable: true,
        releaseMode: false,
        testerBuild: false,
      ),
      isFalse,
    );
    expect(
      service.shouldEnforceMandatoryUpdate(
        forceLatestEnabled: true,
        updateAvailable: true,
        releaseMode: true,
        testerBuild: true,
      ),
      isFalse,
    );
  });

  test("android update URL resolves GitHub latest to pinned release", () {
    final service = LoginUpdateCheckService.forTesting(
      versionLoader: () async => '0.19.0+18',
      isIos: false,
    );

    final resolved = service.resolvePreferredUpdateUrlForTest(
      'https://github.com/marolam/prox/releases/latest/download/app-release.apk',
      targetVersion: '0.19.0+19',
    );

    expect(
      resolved,
      'https://github.com/marolam/prox/releases/download/v0.19.0+19/app-release.apk',
    );
    service.latestResult.dispose();
  });

  test("iOS update URL does not rewrite GitHub latest path", () {
    final service = LoginUpdateCheckService.forTesting(
      versionLoader: () async => '0.19.0+18',
      isIos: true,
    );

    const url =
        'https://github.com/marolam/prox/releases/latest/download/app-release.apk';
    final resolved = service.resolvePreferredUpdateUrlForTest(
      url,
      targetVersion: '0.19.0+19',
    );

    expect(resolved, url);
    service.latestResult.dispose();
  });

  testWidgets("update enforcement gate can render above MaterialApp",
      (tester) async {
    final pending = Completer<UpdateConfigSnapshot>();
    final service = LoginUpdateCheckService.forTesting(
      versionLoader: () async => '1.0.0',
      configLoader: (_) => pending.future,
    );
    await tester.pumpWidget(
      UpdateEnforcementGate(
        service: service,
        child: const MaterialApp(home: Scaffold()),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text("Checking app version..."), findsOneWidget);
    pending.complete(
        const UpdateConfigSnapshot({'update_latest_version': '1.0.0'}));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    service.latestResult.dispose();
  });

  testWidgets("autoupdate prompt shows current and latest version numbers",
      (tester) async {
    LoginUpdateCheckService.instance.resetPromptThrottleForTest();
    late BuildContext promptContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              promptContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    LoginUpdateCheckService.instance.showUpdatePromptForTest(
      promptContext,
      _updateResult(currentVersion: "0.18.0+6", latestVersion: "0.18.0+7"),
    );
    await tester.pump();

    expect(
      find.text("New update available (v0.18.0+7). You are on v0.18.0+6."),
      findsOneWidget,
    );
    expect(find.text("Update"), findsOneWidget);
  });

  testWidgets("autoupdate prompt can show a subsequent newer version",
      (tester) async {
    LoginUpdateCheckService.instance.resetPromptThrottleForTest();
    late BuildContext promptContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              promptContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    LoginUpdateCheckService.instance.showUpdatePromptForTest(
      promptContext,
      _updateResult(currentVersion: "0.18.0+6", latestVersion: "0.18.0+7"),
      throttleByVersion: true,
    );
    await tester.pump();

    expect(
      find.text("New update available (v0.18.0+7). You are on v0.18.0+6."),
      findsOneWidget,
    );

    LoginUpdateCheckService.instance.showUpdatePromptForTest(
      promptContext,
      _updateResult(currentVersion: "0.18.0+6", latestVersion: "0.18.0+8"),
      throttleByVersion: true,
    );
    await tester.pump();

    expect(
      find.text("New update available (v0.18.0+8). You are on v0.18.0+6."),
      findsOneWidget,
    );
  });
}
