import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:app_links/app_links.dart";
import "package:firebase_app_check/firebase_app_check.dart";
import "package:firebase_core/firebase_core.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

import "firebase_options.dart";
import "utils/app_text_scaler.dart";
import "app_router.dart";

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
import "screens/meetup/meetup_live_screen.dart";
import "screens/meetup/meetup_history_screen.dart";
import "screens/business/business_mode_entry_screen.dart";
import "screens/meetup/meetup_planner_screen.dart";
import "screens/meetup/color_match_screen.dart";
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
import "package:prox/services/ime_visibility_service.dart";
import "package:prox/services/login_update_check_service.dart";
import "package:prox/services/referral/referral_attribution.dart";
import "package:prox/services/push_notifications.dart";
import "package:prox/services/startup_watchdog.dart";
import "package:prox/services/user_settings_service.dart";
import "package:prox/theme/prox_ux_theme_builder.dart";
import "package:prox/services/navigation/route_tracker_observer.dart";
import "package:prox/widgets/global_top_actions_bar.dart";
import "package:prox/widgets/update_enforcement_gate.dart";
import "package:prox/widgets/connectivity_status_banner.dart";
import "package:prox/services/runtime_diagnostics_service.dart";

class ProxApp extends StatefulWidget {
  const ProxApp({super.key});

  @override
  State<ProxApp> createState() => _ProxAppState();
}

class _ProxAppState extends State<ProxApp> {
  bool _postInitServicesScheduled = false;
  bool _appCheckActivated = false;
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final RouteTrackerObserver _routeTrackerObserver = RouteTrackerObserver();
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _referralUriSub;

  static const bool _safeMode = bool.fromEnvironment(
    "PROX_SAFE_MODE",
    defaultValue: false,
  );
  static const bool _suspendGlobalOverlaysForImeRecovery = true;

  late Future<void> _firebaseInit = _initializeFirebase();

  Future<void> _initializeFirebase() => _initFirebaseWithRecovery().timeout(
    const Duration(seconds: 30),
    onTimeout: () => throw TimeoutException("Firebase startup timed out"),
  );

  Future<void> _initFirebaseWithRecovery() async {
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

    unawaited(RuntimeDiagnosticsService.instance.initializeFirebase());
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
          providerApple: kReleaseMode
              ? AppleDeviceCheckProvider()
              : AppleDebugProvider(),
        );
        _appCheckActivated = true;
        return;
      default:
        return;
    }
  }

  void _startPostInitServicesOnce() {
    if (_postInitServicesScheduled) return;
    _postInitServicesScheduled = true;
    // The Firebase-backed MaterialApp and navigator must exist before an initial
    // notification is routed. No arbitrary timer or pre-existing login is needed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void startService(String operation, FutureOr<void> Function() action) {
        unawaited(
          Future<void>.sync(action).catchError((
            Object error,
            StackTrace stack,
          ) {
            RuntimeDiagnosticsService.instance.record(
              error,
              stack,
              operation: operation,
            );
          }),
        );
      }

      startService("Account session startup", AuthBootstrap.instance.start);
      startService(
        "Keyboard visibility startup",
        ImeVisibilityService.instance.ensureStarted,
      );
      startService(
        "Preferences startup",
        UserSettingsService.instance.ensureLoaded,
      );
      if (!_safeMode) {
        PushNotifications.instance.registerNavigatorKey(_navKey);
        startService(
          "Notification routing startup",
          PushNotifications.instance.setupMessageOpenHandlers,
        );
        LoginUpdateCheckService.instance.registerNavigatorKey(_navKey);
        LoginUpdateCheckService.instance.startLiveWatcher();
      }
      StartupWatchdog.instance.disarmAfterFirstFrame();
    });
  }

  @override
  void initState() {
    super.initState();
    _initReferralLinks();
  }

  @override
  void dispose() {
    _referralUriSub?.cancel();
    LoginUpdateCheckService.instance.stopLiveWatcher();
    super.dispose();
  }

  void _initReferralLinks() {
    // App Links / deep links can carry referral attribution context (code/token).
    _appLinks
        .getInitialLink()
        .then((Uri? uri) {
          if (uri == null) return;
          unawaited(ReferralAttribution.instance.captureFromLaunchUri(uri));
        })
        .catchError((_) {});

    _referralUriSub = _appLinks.uriLinkStream.listen((Uri uri) {
      unawaited(ReferralAttribution.instance.captureFromLaunchUri(uri));
    });
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
            home: _InitErrorScreen(
              onRetry: () {
                setState(() => _firebaseInit = _initializeFirebase());
              },
            ),
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
                  _routeTrackerObserver,
                ],
                builder: (context, child) {
                  final media = MediaQuery.of(context);
                  final Widget scaledChild = MediaQuery(
                    data: media.copyWith(
                      textScaler: AppTextScaler(
                        systemScaler: media.textScaler,
                        preference: settings.textScaleFactor,
                      ),
                    ),
                    child: ConnectivityStatusBanner(
                      child: child ?? const SizedBox.shrink(),
                    ),
                  );

                  if (_suspendGlobalOverlaysForImeRecovery) {
                    return UpdateEnforcementGate(child: scaledChild);
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
                  return UpdateEnforcementGate(child: base);
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
                  "/nearby": (_) => const MatchInboxScreen(),
                  "/inbox": (_) => const ChatThreadsScreen(),
                  "/chats": (_) => const ChatThreadsScreen(),
                  "/meetups": (_) => const MeetupHistoryScreen(),
                  "/meetup": (_) => const MeetupHistoryScreen(),
                  "/business-mode": (_) => const BusinessModeEntryScreen(),
                  "/business-setup": AppRouter.buildBusinessSetup,

                  // Dev
                  "/dev": (_) => const DevPanel(),
                  "/dev/menu": (_) => const DevMenu(),
                  "/dev/system_health": (_) => const SystemHealthHudScreen(),
                  "/dev/bug_reports": (_) => const BugReportsListScreen(),
                  "/dev/sweep": (_) => const MissingSweepCheckScreen(),
                  "/dev/user-simulator": (_) => const DevUserSimulatorScreen(),

                  // Core flows
                  "/chat": (context) => ChatThreadScreen.fromArgs(
                    ModalRoute.of(context)?.settings.arguments,
                  ),
                  "/meetup_plan": (context) => MeetupPlannerScreen.fromArgs(
                    ModalRoute.of(context)?.settings.arguments,
                  ),
                  "/meetup_live": (context) => MeetupLiveScreen.fromArgs(
                    ModalRoute.of(context)?.settings.arguments,
                  ),
                  "/color-match": (context) => ColorMatchScreen(
                    meetupId: (ModalRoute.of(context)?.settings.arguments ?? "")
                        .toString(),
                  ),
                  "/rate": (context) => RatingScreen.fromArgs(
                    ModalRoute.of(context)?.settings.arguments,
                  ),

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
  final VoidCallback onRetry;
  const _InitErrorScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 16),
              const Text("Prox couldn't start", textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                "Check your connection and try again.",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text("Try again"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
