import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prox/screens/settings/user_guide_screen.dart';
import 'package:prox/screens/store/feature_example_screen.dart';
import 'package:prox/screens/review/release_candidate_checklist_screen.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/theme/prox_ux_theme_builder.dart';

/// Optional rendered review artifacts, separate from golden baselines.
/// flutter test --dart-define=PROX_EXPORT_AUDIT_SCREENSHOTS=true test/frontend_visual_audit_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const export = bool.fromEnvironment('PROX_EXPORT_AUDIT_SCREENSHOTS');
  final screens = <String, Widget>{
    'user_guide': const UserGuideScreen(),
    'pro_example': const FeatureExampleScreen(),
    'release_checklist': const ReleaseCandidateChecklistScreen(),
  };

  setUpAll(() async {
    if (!export) return;
    final fontFile = File(r'C:\Windows\Fonts\segoeui.ttf');
    if (await fontFile.exists()) {
      final loader = FontLoader('AuditFont');
      loader.addFont(
        Future.value(ByteData.sublistView(await fontFile.readAsBytes())),
      );
      await loader.load();
    }
    final iconFile = File(
      'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
    );
    if (await iconFile.exists()) {
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        Future.value(ByteData.sublistView(await iconFile.readAsBytes())),
      );
      await icons.load();
    }
  });

  for (final entry in screens.entries) {
    testWidgets('render ${entry.key} at phone size', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundaryKey = GlobalKey();
      final appTheme = ProxUxThemeBuilder.buildFor(
        const UserSettings.defaults(),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme.copyWith(
              textTheme: appTheme.textTheme.apply(fontFamily: 'AuditFont'),
              primaryTextTheme: appTheme.primaryTextTheme.apply(
                fontFamily: 'AuditFont',
              ),
            ),
            home: entry.value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final screenshot = await boundary.toImage(pixelRatio: 2);
        final png = await screenshot.toByteData(format: ui.ImageByteFormat.png);
        screenshot.dispose();
        final directory = Directory('artifacts/audit_ui');
        await directory.create(recursive: true);
        await File(
          '${directory.path}/${entry.key}.png',
        ).writeAsBytes(png!.buffer.asUint8List());
      });
    }, skip: !export);
  }
}
