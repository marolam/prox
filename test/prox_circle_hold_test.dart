import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/widgets/prox_circle_hold.dart';

void main() {
  Future<void> showCircle(
    WidgetTester tester,
    VoidCallback activate, {
    ValueChanged<double>? progress,
    ScrollController? scroll,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          controller: scroll,
          child: Column(
            children: [
              ProxCircleHold(
                onHold: activate,
                onProgress: progress ?? (_) {},
                child: const SizedBox(
                  width: 196,
                  height: 196,
                  child: Text('Prox'),
                ),
              ),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets('tap and short hold never activate', (tester) async {
    var activations = 0;
    await showCircle(tester, () => activations++);
    final center = tester.getCenter(find.byType(ProxCircleHold));
    await tester.tapAt(center);
    await tester.pump(const Duration(seconds: 4));
    expect(activations, 0);
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 2900));
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    expect(activations, 0);
  });

  testWidgets('movement inside circle preserves hold and does not scroll', (
    tester,
  ) async {
    var activations = 0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await showCircle(tester, () => activations++, scroll: scroll);
    final center = tester.getCenter(find.byType(ProxCircleHold));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(seconds: 1));
    await gesture.moveTo(center + const Offset(50, 30));
    await tester.pump(const Duration(seconds: 1));
    await gesture.moveTo(center + const Offset(-40, -40));
    await tester.pump(const Duration(milliseconds: 1010));
    expect(activations, 1);
    expect(scroll.offset, 0);
    await tester.pump(const Duration(seconds: 3));
    await gesture.up();
    expect(activations, 1);
  });

  testWidgets(
    'leaving circle cancels until a fresh touch, even after reentry',
    (tester) async {
      var activations = 0;
      await showCircle(tester, () => activations++);
      final center = tester.getCenter(find.byType(ProxCircleHold));
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(seconds: 2));
      await gesture.moveTo(center + const Offset(120, 0));
      await gesture.moveTo(center);
      await tester.pump(const Duration(seconds: 4));
      expect(activations, 0);
      await gesture.up();
      final fresh = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 3010));
      expect(activations, 1);
      await fresh.up();
    },
  );

  testWidgets('system pointer cancellation and app background cancel holds', (
    tester,
  ) async {
    var activations = 0;
    await showCircle(tester, () => activations++);
    final center = tester.getCenter(find.byType(ProxCircleHold));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(seconds: 2));
    await gesture.cancel();
    await tester.pump(const Duration(seconds: 2));
    expect(activations, 0);
    final next = await tester.startGesture(center);
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 4));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await next.up();
    expect(activations, 0);
  });

  testWidgets(
    'a second finger cannot finish or cancel the owning finger hold',
    (tester) async {
      var activations = 0;
      await showCircle(tester, () => activations++);
      final center = tester.getCenter(find.byType(ProxCircleHold));
      final first = await tester.startGesture(center, pointer: 1);
      await tester.pump(const Duration(seconds: 1));
      final second = await tester.startGesture(
        center + const Offset(20, 20),
        pointer: 2,
      );
      await second.up();
      await tester.pump(const Duration(milliseconds: 2010));
      expect(activations, 1);
      await first.up();
    },
  );
}
