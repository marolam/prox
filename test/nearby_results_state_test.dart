import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/geoquery_service.dart';
import 'package:prox/widgets/location_issue_banner.dart';

Widget _screen({
  GeoQueryStatus status = GeoQueryStatus.ready,
  bool locationEnabled = true,
  bool matchingEnabled = true,
  bool loading = false,
  bool failed = false,
  bool retrying = false,
  VoidCallback? retry,
  VoidCallback? settings,
  double scale = 1,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: NearbyResultsGate(
      status: status,
      locationEnabled: locationEnabled,
      matchingEnabled: matchingEnabled,
      queryLoading: loading,
      queryFailed: failed,
      retrying: retrying,
      onRetry: retry ?? () {},
      onSettings: settings ?? () {},
      child: const Text('No matches nearby'),
    ),
  ),
);

void main() {
  for (final status in GeoQueryStatus.values.where(
    (value) => value != GeoQueryStatus.ready,
  )) {
    testWidgets('$status never displays a successful empty search', (
      tester,
    ) async {
      await tester.pumpWidget(_screen(status: status));
      expect(find.text('No matches nearby'), findsNothing);
      expect(find.textContaining('/users/'), findsNothing);
      expect(find.textContaining('geopoint'), findsNothing);
      expect(find.textContaining('Signed in:'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'a query failure has a working retry action even with a known location',
    (tester) async {
      var retries = 0;
      await tester.pumpWidget(_screen(failed: true, retry: () => retries++));
      expect(find.text('Nearby is unavailable'), findsOneWidget);
      expect(find.text('No matches nearby'), findsNothing);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    },
  );

  testWidgets(
    'location opt-out stays paused and offers settings without an automatic retry',
    (tester) async {
      var opens = 0;
      await tester.pumpWidget(
        _screen(locationEnabled: false, settings: () => opens++),
      );
      expect(find.text('Location is off'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('No matches nearby'), findsNothing);
      await tester.tap(find.text('Location settings'));
      expect(opens, 1);
    },
  );

  testWidgets(
    'matching off explains the paused state without declaring an empty area',
    (tester) async {
      await tester.pumpWidget(_screen(matchingEnabled: false));
      expect(find.text('Matching is off'), findsOneWidget);
      expect(find.text('No matches nearby'), findsNothing);
    },
  );

  testWidgets(
    'retry and pending query hide old empty results until a successful response',
    (tester) async {
      await tester.pumpWidget(
        _screen(status: GeoQueryStatus.queryError, retrying: true),
      );
      expect(find.text('Checking nearby again…'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('No matches nearby'), findsNothing);
      await tester.pumpWidget(_screen(loading: true));
      expect(find.text('Finding nearby matches…'), findsOneWidget);
      expect(find.text('No matches nearby'), findsNothing);
      await tester.pumpWidget(_screen());
      expect(find.text('No matches nearby'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'location recovery actions remain usable with large text in a short narrow panel',
    (tester) async {
      tester.view.physicalSize = const Size(320, 260);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _screen(status: GeoQueryStatus.locationUnavailable, scale: 1.6),
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Location settings'), 180);
      await tester.pump();
      expect(find.text('Location settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
