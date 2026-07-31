import "dart:async";
import "dart:ui" as ui;

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:firebase_app_check/firebase_app_check.dart";
import "package:firebase_core/firebase_core.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

import "firebase_options.dart";

import "screens/account/account_billing_screen.dart";
import "screens/auth/auth_gate.dart";
import "screens/chat/chat_thread_screen.dart";
import "screens/chats/chat_threads_screen.dart";
import "screens/dashboard/dashboard_screen.dart";
import "screens/dev/dev_menu.dart";
import "screens/dev/dev_panel.dart";
import "screens/dev/system_health_hud_screen.dart";
import "screens/dev/missing_sweep_check_screen.dart";
import "dev/dev_user_simulator_screen.dart";
import "screens/matches/match_inbox_screen.dart";
import "screens/matches/matches_screen.dart";
import "screens/meetup/meetup_live_screen.dart";
import "screens/meetup/meetup_planner_screen.dart";
import "screens/notifications/notifications_feed_screen.dart";
import "screens/onboarding/onboarding_screen.dart";
import "screens/onboarding/profile_setup_screen.dart";
import "screens/policy/policy_hub_screen.dart";
import "screens/rating/rating_screen.dart";
import "screens/referral/referrals_hub_screen.dart";
import "screens/review/release_candidate_checklist_screen.dart";
import "screens/review/tester_mission_screen.dart";
import "screens/settings/settings_screen.dart";
import "screens/splash_screen.dart";
import "screens/store/prox_points_store_screen.dart";
import "screens/support/support_hub_screen.dart";
import "screens/system/unknown_route_screen.dart";
import "screens/tester/tester_insight_mode_screen.dart";
import "screens/tester/tester_menu_screen.dart";
import "home/home_root_shell.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/screens/dev/bug_reports/bug_reports_list_screen.dart";
import "package:prox/services/auth/auth_bootstrap.dart";
import "package:prox/services/bug_reporting/bug_report_service.dart";
import "package:prox/services/critical_ui_service.dart";
import "package:prox/services/dev/cost_hud_service.dart";
import "package:prox/services/ime_visibility_service.dart";
import "package:prox/services/login_update_check_service.dart";
import "package:prox/services/presence_pulse/presence_pulse_service.dart";
import "package:prox/services/push_notifications.dart";
import "package:prox/services/startup_watchdog.dart";
import "package:prox/services/user_settings_service.dart";
import "package:prox/theme/prox_ux_theme_builder.dart";
import "package:prox/services/navigation/route_tracker_observer.dart";
import "package:prox/widgets/bug_reporting/bug_report_overlay.dart";
import "package:prox/widgets/dev/cost_hud_overlay.dart";
import "package:prox/widgets/global_top_actions_bar.dart";

class ProxApp extends StatefulWidget {
  const ProxApp({super.key});

  @override
  State<ProxApp> createState() => _ProxAppState();
}

class _ProxAppState extends State<ProxApp> {
  bool _postInitServicesStarted = false;
  bool _postInitServicesScheduled = false;
  bool _appCheckActivated = false;
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final RouteTrackerObserver _routeTrackerObserver = RouteTrackerObserver();

  static const bool _safeMode =
      bool.fromEnvironment("PROX_SAFE_MODE", defaultValue: false);
  static const bool _suspendGlobalOverlaysForImeRecovery = true;

  late final Future<void> _firebaseInit = _initFirebaseWithRecovery().timeout(
    const Duration(seconds: 30),
    onTimeout: () => throw TimeoutException("Firebase startup timed out"),
  );

  Future<void> _initFirebaseWithRecovery() async {
    const minHold = Duration(milliseconds: 700);
    final sw = Stopwatch()..start();
    bool retried = false;
    while (true) {
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          ).timeout(const Duration(seconds: 12));
        }

        try {
          await _activateAppCheckIfSupported();
        } catch (e) {
          debugPrint("[AppInit] App Check activation skipped/failed: $e");
        }

        break; // Success
      } catch (e) {
        final msg = e.toString();

        // Detect SQLite corruption error
        if (!retried &&
            (msg.contains("SQLiteDatabaseCorruptException") ||
                msg.contains("database disk image is malformed") ||
                msg.contains("SQLITE_CORRUPT"))) {
          try {
            await FirebaseFirestore.instance.terminate();
            await FirebaseFirestore.instance.clearPersistence();
            retried = true;
            continue; // Retry init
          } catch (_) {
            rethrow;
          }
        }
        rethrow;
      }
    }

    StartupWatchdog.instance.disarm();

    final remaining = minHold - sw.elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }
  }

  Future<void> _activateAppCheckIfSupported() async {
    if (_appCheckActivated) return;
    if (kIsWeb) return;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        await FirebaseAppCheck.instance.activate(
          providerAndroid: kReleaseMode
              ? AndroidPlayIntegrityProvider()
              : AndroidDebugProvider(),
        );
        _appCheckActivated = true;
        return;
      case TargetPlatform.iOS:
        await FirebaseAppCheck.instance.activate(
          providerApple:
              kReleaseMode ? AppleDeviceCheckProvider() : AppleDebugProvider(),
        );
        _appCheckActivated = true;
        return;
      default:
        return;
    }
  }

  void _startPostInitServicesOnce() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
    };
    ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      final err = error.toString();
      if (err.contains("[cloud_firestore/permission-denied]")) {
        debugPrint(
            "[AppInit] Firestore permission issue handled during startup.");
        return true;
      }
      debugPrint("[AppInit] Unhandled async error: $error");
      return true;
    };
    if (_postInitServicesScheduled) return;
    _postInitServicesScheduled = true;

    try {
      ImeVisibilityService.instance.ensureStarted();
    } catch (e) {
      debugPrint("[AppInit] IME visibility start failed: $e");
    }
    try {
      UserSettingsService.instance.ensureLoaded();
    } catch (e) {
      debugPrint("[AppInit] user settings preload failed: $e");
    }

    if (!_safeMode) {
      Future<void>.delayed(const Duration(seconds: 6), () async {
        if (!mounted) return;
        if (CriticalUiService.instance.isActive) {
          // Keep retrying while a critical UI (like profile editing) is active.
          while (mounted && CriticalUiService.instance.isActive) {
            await Future<void>.delayed(const Duration(seconds: 2));
          }
          if (!mounted) return;
        }

        if (_postInitServicesStarted) return;

        final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
        if (uid.trim().isEmpty) {
          // Keep login/onboarding responsive; defer auth-bound services until a user exists.
          return;
        }

        _postInitServicesStarted = true;

        try {
          PresencePulseService.instance.start();
        } catch (e) {
          debugPrint("[AppInit] presence pulse start failed: $e");
        }
        try {
          BugReportService.instance.ensureReady();
        } catch (e) {
          debugPrint("[AppInit] bug report service start failed: $e");
        }
        try {
          CostHudService.instance.ensureReady();
        } catch (e) {
          debugPrint("[AppInit] cost HUD service start failed: $e");
        }

        try {
          // ignore: discarded_futures
          AuthBootstrap.instance.start();
        } catch (e) {
          debugPrint("[AppInit] auth bootstrap start failed: $e");
        }

        try {
          // ignore: discarded_futures
          PushNotifications.instance.setupMessageOpenHandlers();
        } catch (e) {
          debugPrint("[AppInit] push message-open handlers setup failed: $e");
        }
      });

      try {
        PushNotifications.instance.registerNavigatorKey(_navKey);
      } catch (e) {
        debugPrint("[AppInit] push navigator key registration failed: $e");
      }

      try {
        LoginUpdateCheckService.instance.registerNavigatorKey(_navKey);
        LoginUpdateCheckService.instance.startLiveWatcher();
      } catch (e) {
        debugPrint("[AppInit] live update watcher start failed: $e");
      }
    }

    StartupWatchdog.instance.disarmAfterFirstFrame();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _firebaseInit,
      builder: (context, snap) {
        Widget child;

        if (snap.connectionState != ConnectionState.done) {
          child = const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: SplashScreen(),
          );
        } else if (snap.hasError) {
          child = MaterialApp(
            debugShowCheckedModeBanner: false,
            home: _InitErrorScreen(err: snap.error.toString()),
          );
        } else {
          _startPostInitServicesOnce();

          child = StreamBuilder<UserSettings>(
            stream: UserSettingsService.instance.watch(),
            builder: (context, s) {
              final settings = s.data ?? UserSettingsService.instance.current;
              final ThemeData theme = ProxUxThemeBuilder.buildFor(settings);

              return MaterialApp(
                debugShowCheckedModeBanner: false,
                navigatorKey: _navKey,
                theme: theme,
                darkTheme: theme,
                themeMode: ThemeMode.dark,
                initialRoute: "/auth",
                navigatorObservers: <NavigatorObserver>[
                  BugReportService.instance.routeObserver,
                  CostHudService.instance.routeObserver,
                  _routeTrackerObserver,
                ],
                builder: (context, child) {
                  final scale = settings.textScaleFactor.clamp(0.9, 1.6);
                  final media = MediaQuery.of(context);
                  final Widget scaledChild = MediaQuery(
                    data: media.copyWith(textScaler: TextScaler.linear(scale)),
                    child: child ?? const SizedBox.shrink(),
                  );

                  if (_suspendGlobalOverlaysForImeRecovery) {
                    return scaledChild;
                  }

                  final Widget base = Stack(
                    children: [
                      scaledChild,
                      GlobalTopActionsBar(
                        routeTracker: _routeTrackerObserver,
                        navigatorKey: _navKey,
                      ),
                    ],
                  );
                  if (_safeMode) return base;

                  final Widget withBug = BugReportOverlay(
                    enabled: BugReportService.instance.isEnabledForThisBuild,
                    child: base,
                  );
                  return CostHudOverlay(
                    enabled: CostHudService.instance.isEnabledForThisBuild,
                    child: withBug,
                  );
                },
                onGenerateRoute: (_) => null,
                onUnknownRoute: (settings) {
                  return MaterialPageRoute(
                    builder: (_) => UnknownRouteScreen(name: settings.name),
                  );
                },
                routes: {
                  // Keep root route recoverable: never strand users on a static splash page.
                  "/": (_) => const AuthGate(),
                  "/auth": (_) => const AuthGate(),
                  "/onboarding": (_) => const OnboardingScreen(),

                  // Compatibility onboarding alias
                  "/profile_setup": (_) => const ProfileSetupScreen(),

                  "/home": (_) => const HomeRootShell(),
                  "/matches": (_) => const MatchesScreen(),
                  "/nearby": (_) => const MatchInboxScreen(),
                  "/inbox": (_) => const ChatThreadsScreen(),

                  // Dev
                  "/dev": (_) => const DevPanel(),
                  "/dev/menu": (_) => const DevMenu(),
                  "/dev/system_health": (_) => const SystemHealthHudScreen(),
                  "/dev/bug_reports": (_) => const BugReportsListScreen(),
                  "/dev/sweep": (_) => const MissingSweepCheckScreen(),
                  "/dev/user-simulator": (_) => const DevUserSimulatorScreen(),

                  // Core flows
                  "/chat": (context) => ChatThreadScreen.fromArgs(
                      ModalRoute.of(context)?.settings.arguments),
                  "/meetup_plan": (context) => MeetupPlannerScreen.fromArgs(
                      ModalRoute.of(context)?.settings.arguments),
                  "/meetup_live": (context) => MeetupLiveScreen.fromArgs(
                      ModalRoute.of(context)?.settings.arguments),
                  "/rate": (context) => RatingScreen.fromArgs(
                      ModalRoute.of(context)?.settings.arguments),

                  // Hubs
                  "/dashboard": (_) => const DashboardScreen(),
                  "/store": (_) => const ProxPointsStoreScreen(),
                  "/support": (_) => const SupportHubScreen(),
                  "/referrals": (_) => const ReferralsHubScreen(),
                  "/account": (_) => const AccountBillingScreen(),
                  "/policy": (_) => const PolicyHubScreen(),
                  "/notifications": (_) => const NotificationsFeedScreen(),
                  "/settings": (_) => const SettingsScreen(),

                  // Review
                  "/rc_checklist": (_) =>
                      const ReleaseCandidateChecklistScreen(),
                  "/tester-mission": (_) => const TesterMissionScreen(),
                  "/tester-insight": (_) => const TesterInsightModeScreen(),
                  "/tester-menu": (_) => const TesterMenuScreen(),
                },
              );
            },
          );
        }

        return child;
      },
    );
  }
}

class _InitErrorScreen extends StatelessWidget {
  final String err;
  const _InitErrorScreen({required this.err});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "Startup failed:\n\n$err",
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
