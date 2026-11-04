import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/widgets/safety_access_shell.dart';

void main() {
  testWidgets('keeps routed content above the system navigation inset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.reset);

    final contentKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            SafetyAccessShell(child: child ?? const SizedBox.shrink()),
        home: Scaffold(body: SizedBox.expand(key: contentKey)),
      ),
    );

    expect(
      tester.getBottomLeft(find.byKey(contentKey)).dy,
      lessThanOrEqualTo(776),
    );
  });
}
