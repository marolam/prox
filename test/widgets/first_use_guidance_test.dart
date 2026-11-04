import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/screens/onboarding/onboarding_screen.dart';
import 'package:prox/screens/referral/referral_demo_walkthrough_screen.dart';
import 'package:prox/services/first_use_service.dart';
import 'package:prox/services/user_settings_service.dart';
import 'package:prox/services/simple_mode/simple_mode_policy.dart';
import 'package:prox/widgets/first_use_guidance.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> tapVisible(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  void smallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.reset);
  }

  Widget app(Widget child, {double scale = 1}) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: child,
  );

  testWidgets(
    'new-user welcome is scroll safe and explains optional invitations',
    (tester) async {
      smallScreen(tester);
      final service = FirstUseService('new-widget');
      await tester.pumpWidget(
        app(
          FirstUseWelcomeGate(
            service: service,
            autoWelcome: true,
            child: const Scaffold(body: Text('Profile setup')),
          ),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Prox'), findsOneWidget);
      expect(find.textContaining('no recruiting quota'), findsOneWidget);
      expect(find.textContaining('in-person verification'), findsOneWidget);
      expect(find.text('Profile setup'), findsNothing);
      expect(tester.takeException(), isNull);
      await tapVisible(tester, 'Show me how');
      expect(service.touring, isTrue);
      expect(find.text('Profile setup'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('existing accounts enter without an unsolicited welcome', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FirstUseWelcomeGate(
          service: FirstUseService('existing-widget'),
          autoWelcome: false,
          child: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Welcome to Prox'), findsNothing);
  });

  testWidgets('storage errors expose retry and an explicit continue option', (
    tester,
  ) async {
    final service = FirstUseService('broken-widget');
    SharedPreferences.setMockInitialValues({service.storageKey: 'not json'});
    await tester.pumpWidget(
      app(
        FirstUseWelcomeGate(
          service: service,
          autoWelcome: true,
          child: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await tapVisible(tester, 'Continue without saving guide progress');
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets(
    'tour can move back, pause, resume, and finish without real actions',
    (tester) async {
      final service = FirstUseService('tour-widget');
      await service.startTour();
      await tester.pumpWidget(
        app(
          Scaffold(
            body: ListenableBuilder(
              listenable: service,
              builder: (_, _) => service.touring
                  ? FirstUseTourCard(
                      service: service,
                      locked: service.step >= 4,
                    )
                  : const Text('Tour paused or finished'),
            ),
          ),
        ),
      );
      await tapVisible(tester, 'Next');
      expect(service.step, 1);
      await tapVisible(tester, 'Back');
      expect(service.step, 0);
      await tapVisible(tester, 'Next');
      await tapVisible(tester, 'Finish later');
      expect(service.touring, isFalse);
      expect(service.step, 1);
      await service.startTour();
      await tester.pumpAndSettle();
      for (var index = 1; index < firstUseStops.length - 1; index++) {
        expect(service.step, index);
        if (index >= 4) {
          expect(
            find.textContaining('restricted in Simple Mode'),
            findsOneWidget,
          );
        }
        await tapVisible(tester, 'Next');
      }
      await tapVisible(tester, 'Finish tour');
      expect(service.finished, isTrue);
      expect(service.completed, {'nearby', 'connections', 'invitation'});
      expect(service.completed, isNot(contains('profile')));
      expect(service.completed, isNot(contains('keywords')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all tour steps fit small screens with large text and keyboard insets',
    (tester) async {
      smallScreen(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      final service = FirstUseService('small-tour');
      await service.startTour();
      await tester.pumpWidget(
        app(
          Scaffold(
            body: SafeArea(
              child: ListenableBuilder(
                listenable: service,
                builder: (_, _) =>
                    FirstUseTourCard(service: service, locked: true),
              ),
            ),
          ),
          scale: 2,
        ),
      );
      for (var index = 0; index < firstUseStops.length; index++) {
        await service.moveTo(index);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Finish later'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getBottomLeft(find.text('Finish later')).dy,
          lessThanOrEqualTo(568 - 180),
        );
      }
    },
  );

  testWidgets(
    'checklist contains learning steps, never an invitation or match quota',
    (tester) async {
      final service = FirstUseService('checklist-widget');
      await service.startTour();
      final opened = <String>[];
      await tester.pumpWidget(
        app(
          Scaffold(
            body: SingleChildScrollView(
              child: FirstStepsCard(service: service, onOpen: opened.add),
            ),
          ),
        ),
      );
      await tapVisible(tester, 'Your first steps: 0 of 5');
      await tapVisible(tester, 'Learn to share your in-person QR');
      expect(opened, ['invitation']);
      expect(service.completed, isEmpty);
      await tapVisible(tester, 'Hide checklist');
      expect(service.hidden, isTrue);
    },
  );

  testWidgets('context tips are dismissible and persist independently', (
    tester,
  ) async {
    final service = FirstUseService('tip-widget');
    await service.startTour();
    await tester.pumpWidget(
      app(
        Scaffold(
          body: ListenableBuilder(
            listenable: service,
            builder: (_, _) => SingleChildScrollView(
              child: FirstUseFeatureTip(service: service, tab: 'Nearby'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('First visit: Nearby'), findsOneWidget);
    await tapVisible(tester, 'First visit: Nearby');
    await tapVisible(tester, 'Got it');
    expect(find.text('First visit: Nearby'), findsNothing);
    final restored = FirstUseService('tip-widget');
    await restored.load();
    expect(restored.tipsSeen, {'Nearby'});
  });

  testWidgets('profile introduction is scroll safe at large text', (
    tester,
  ) async {
    smallScreen(tester);
    await tester.pumpWidget(app(const OnboardingScreen(), scale: 2));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Start quick setup'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomLeft(find.text('Start quick setup')).dy,
      lessThanOrEqualTo(544),
    );
  });

  testWidgets('optional example walkthrough can be exited without completion', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (_) =>
                      const ReferralDemoWalkthroughScreen(allowExit: true),
                ),
              ),
              child: const Text('Open demo'),
            ),
          ),
        ),
      ),
    );
    await tapVisible(tester, 'Open demo');
    expect(find.text('Examples only'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Open demo'), findsOneWidget);
  });

  testWidgets('invitation education is visible without creating any QR', (
    tester,
  ) async {
    smallScreen(tester);
    await tester.pumpWidget(
      app(
        const Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(child: InvitationGuideCard()),
          ),
        ),
        scale: 2,
      ),
    );
    await tester.ensureVisible(find.text('I understand these steps'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not guaranteed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('QR shortcut cannot bypass Simple Mode or create a token', (
    tester,
  ) async {
    final settings = UserSettingsService.instance;
    final previous = settings.current;
    settings.setAlwaysUseNormalMode(false);
    settings.setSimpleModeEnabled(true);
    addTearDown(() {
      settings.setSimpleModeEnabled(previous.simpleModeEnabled);
      settings.setAlwaysUseNormalMode(previous.alwaysUseNormalMode);
    });
    var routesOpened = 0;
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/referrals': (_) {
            routesOpened++;
            return const Scaffold(body: Text('Invitation controls'));
          },
        },
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openInvitationQr(context),
              child: const Text('Show my invitation QR'),
            ),
          ),
        ),
      ),
    );
    await tapVisible(tester, 'Show my invitation QR');
    expect(SimpleModePolicy.isActive, isTrue);
    expect(routesOpened, 0);
    expect(find.textContaining('restricted in Simple Mode'), findsOneWidget);
    settings.setSimpleModeEnabled(false);
    await tapVisible(tester, 'Show my invitation QR');
    expect(routesOpened, 1);
    expect(find.text('Invitation controls'), findsOneWidget);
  });

  testWidgets(
    'learning panel preserves at least 70 percent of routed content and hides for keyboard',
    (tester) async {
      smallScreen(tester);
      final service = FirstUseService('bounded-panel');
      await service.startTour();
      service.pauseTour();
      final contentKey = GlobalKey();
      final layoutKey = GlobalKey();
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: SafeArea(
                child: SizedBox(
                  key: layoutKey,
                  child: FirstUseLearningLayout(
                    service: service,
                    keyboardVisible:
                        MediaQuery.viewInsetsOf(context).bottom > 0,
                    tab: 'Nearby',
                    onOpen: (_) {},
                    child: SizedBox.expand(key: contentKey),
                  ),
                ),
              ),
              bottomNavigationBar: const SafeArea(
                top: false,
                child: SizedBox(height: 76),
              ),
            ),
          ),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      final available = tester.getSize(find.byKey(layoutKey)).height;
      expect(
        tester.getSize(find.byKey(contentKey)).height,
        greaterThanOrEqualTo(available * .70 - .01),
      );
      expect(
        tester.getBottomLeft(find.byKey(contentKey)).dy,
        lessThanOrEqualTo(568 - 24 - 76),
      );
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      await tester.pumpAndSettle();
      expect(find.text('First visit: Nearby'), findsNothing);
      expect(
        tester.getSize(find.byKey(contentKey)).height,
        tester.getSize(find.byKey(layoutKey)).height,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
