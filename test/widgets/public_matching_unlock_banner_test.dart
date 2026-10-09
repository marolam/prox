import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/matching_access_service.dart';
import 'package:prox/widgets/public_matching_unlock_banner.dart';

void main() {
  testWidgets(
    'unlock notice fits narrow enlarged text and stays dismissed across sessions',
    (tester) async {
      final clock = DateTime.utc(2026, 10, 7);
      int? acknowledged;
      var acknowledgements = 0;
      MatchingAccessService createService() => MatchingAccessService(
        accountChanges: () => const Stream.empty(),
        currentUid: () => 'alice',
        watchReceipt: (_) => const Stream.empty(),
        loadAccess: (_) async => {
          'publicUnlocked': true,
          'publicUnlockedAt': clock.millisecondsSinceEpoch,
          'publicUnlockNotifiedAt': acknowledged,
          'checkedAt': clock.millisecondsSinceEpoch,
          'latitude': 0.0,
          'longitude': 0.0,
          'partyScope': 'public',
        },
        acknowledgeUnlock: (_) async {
          acknowledgements++;
          acknowledged = clock.millisecondsSinceEpoch;
        },
        currentLocation: () => {
          'latitude': 0.0,
          'longitude': 0.0,
          'locationTs': clock.millisecondsSinceEpoch,
        },
        now: () => clock,
        applyAccess: (_, _) {},
      );
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget app(MatchingAccessService service) => MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 227,
                  child: SingleChildScrollView(
                    child: PublicMatchingUnlockBanner(service: service),
                  ),
                ),
                const Expanded(child: Center(child: Text('Nearby'))),
              ],
            ),
          ),
        ),
      );
      final first = createService();
      await first.refresh();
      await tester.pumpWidget(app(first));
      expect(find.text('Public matching is now available'), findsOneWidget);
      expect(find.textContaining('automatically expanded'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Got it'),
        150,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text('Public matching is now available'), findsNothing);
      expect(acknowledgements, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      first.dispose();
      final second = createService();
      await second.refresh();
      await tester.pumpWidget(app(second));
      expect(find.text('Public matching is now available'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      second.dispose();
    },
  );
}
