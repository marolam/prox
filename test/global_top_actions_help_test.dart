import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/navigation/route_tracker_observer.dart";
import "package:prox/widgets/global_top_actions_bar.dart";

void main() {
  tearDown(() {
    ContextHelpService.instance.setContext(null);
  });

  Future<void> _pumpTopBar(
    WidgetTester tester, {
    required String routeName,
    required String? contextKey,
  }) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final routeTracker = RouteTrackerObserver()..currentRoute.value = routeName;
    ContextHelpService.instance.setContext(contextKey);

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: Stack(
            children: [
              const SizedBox.expand(),
              GlobalTopActionsBar(
                routeTracker: routeTracker,
                navigatorKey: navigatorKey,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("shows help action on non-Nearby contexts", (tester) async {
    await _pumpTopBar(
      tester,
      routeName: "/matches",
      contextKey: "home:matches",
    );

    expect(find.byTooltip("How to use this page"), findsOneWidget);
  });

  testWidgets("shows help on Nearby route when context is not Nearby", (tester) async {
    await _pumpTopBar(
      tester,
      routeName: "/nearby",
      contextKey: "home:matches",
    );

    expect(find.byTooltip("How to use this page"), findsOneWidget);
  });

  testWidgets("hides global help actions when Nearby context is active", (tester) async {
    await _pumpTopBar(
      tester,
      routeName: "/matches",
      contextKey: "home:nearby",
    );

    expect(find.byTooltip("How to use this page"), findsNothing);
  });

}
