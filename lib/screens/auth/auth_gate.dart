import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/screens/auth/sign_in_screen.dart";
import "package:prox/screens/location/location_permission_blocked_screen.dart";
import "package:prox/screens/location/location_permission_explainer_screen.dart";
import "package:prox/screens/onboarding/onboarding_screen.dart";
import "package:prox/screens/onboarding/presence_rehearsal_screen.dart";
import "package:prox/services/local_flags.dart";
import "package:prox/services/location_permissions.dart";
import "package:prox/services/monetization_service.dart";
import "package:prox/services/presence_writer.dart";
import "package:prox/services/push_notifications.dart";
import "package:prox/services/referral/referral_attribution.dart";
import "package:prox/services/party_service.dart";
import "package:prox/services/simple_mode/simple_mode_service.dart";
import "package:prox/services/user_settings_service.dart";
import "package:prox/shell/home_root_shell.dart";
import "package:prox/widgets/motion/motion.dart";

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<User?>? _authSub;
  Timer? _nullGraceTimer;
  Timer? _authFallbackTimer;

  User? _resolvedUser;
  bool _authResolved = false;
  int _nullRevision = 0;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthEvent);
    _authFallbackTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _authResolved) return;
      setState(() {
        _authResolved = true;
        _resolvedUser = FirebaseAuth.instance.currentUser;
      });
    });
  }

  void _onAuthEvent(User? user) {
    if (!mounted) return;

    if (user != null) {
      _authFallbackTimer?.cancel();
      _nullGraceTimer?.cancel();
      setState(() {
        _authResolved = true;
        _resolvedUser = user;
      });
      return;
    }

    // Avoid transient null -> user startup flicker by giving auth restore a short grace window.
    final int rev = ++_nullRevision;
    _nullGraceTimer?.cancel();
    _nullGraceTimer = Timer(const Duration(milliseconds: 550), () {
      if (!mounted || rev != _nullRevision) return;
      setState(() {
        _authResolved = true;
        _resolvedUser = null;
      });
    });
  }

  @override
  void dispose() {
    _authFallbackTimer?.cancel();
    _nullGraceTimer?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_authResolved) {
      return const _SplashLoading();
    }

    final User? user = _resolvedUser;
    if (user == null) {
      // Referrals do NOT block entry. Referral codes act as a warming signal (applied post-auth if present).
      return const SignInScreen();
    }

    return _ProfileGate(uid: user.uid);
  }
}

class _ProfileGate extends StatefulWidget {
  const _ProfileGate({required this.uid});

  final String uid;

  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  late final Future<_ProfileGateDecision> _decision = _loadDecision();

  Future<_ProfileGateDecision> _loadDecision() async {
    final FirebaseFirestore db = FirebaseFirestore.instance;

    try {
      final snap = await db
          .collection("users")
          .doc(widget.uid)
          .get()
          .timeout(const Duration(seconds: 10));

      if (!snap.exists) {
        return _fallbackDecisionForMissingProfile();
      }

      final data = snap.data();
      if (data == null) {
        return _fallbackDecisionForMissingProfile();
      }

      final bool profileComplete = _isProfileComplete(data);
      if (!profileComplete) {
        if (SimpleModeService.isEnabledByDefault) {
          return const _ProfileGateDecision.home();
        }
        return const _ProfileGateDecision.onboarding();
      }

      final bool seen = (data["presenceRehearsalSeen"] as bool?) ?? false;
      return _ProfileGateDecision(
        route: seen ? _ProfileGateRoute.home : _ProfileGateRoute.presenceRehearsal,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint("[AuthGate] profile gate fallback for uid=${widget.uid}: $e");
      }
      return const _ProfileGateDecision.home();
    }
  }

  _ProfileGateDecision _fallbackDecisionForMissingProfile() {
    final user = FirebaseAuth.instance.currentUser;
    final creation = user?.metadata.creationTime;
    final lastSignIn = user?.metadata.lastSignInTime;
    final now = DateTime.now();

    final bool newlyCreated = creation != null &&
        now.difference(creation) < const Duration(hours: 6) &&
        lastSignIn != null &&
        lastSignIn.difference(creation).inMinutes.abs() <= 5;

    if (newlyCreated) {
      if (SimpleModeService.isEnabledByDefault) {
        return const _ProfileGateDecision.home();
      }
      return const _ProfileGateDecision.onboarding();
    }

    if (kDebugMode) {
      debugPrint(
        "[AuthGate] profile doc missing for existing user uid=${widget.uid}; allowing app shell fallback",
      );
    }
    return const _ProfileGateDecision.home();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ProfileGateDecision>(
      future: _decision,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SplashLoading();
        }

        final decision = snapshot.data ?? const _ProfileGateDecision.home();
        switch (decision.route) {
          case _ProfileGateRoute.onboarding:
            return const OnboardingScreen();
          case _ProfileGateRoute.presenceRehearsal:
            ReferralAttribution.instance.markProfileComplete(uid: widget.uid);
            return PresenceRehearsalScreen(uid: widget.uid);
          case _ProfileGateRoute.home:
            ReferralAttribution.instance.markProfileComplete(uid: widget.uid);
            return _PostAuthBootstrapShell(uid: widget.uid);
        }
      },
    );
  }
}

enum _ProfileGateRoute {
  onboarding,
  presenceRehearsal,
  home,
}

class _ProfileGateDecision {
  final _ProfileGateRoute route;

  const _ProfileGateDecision({required this.route});

  const _ProfileGateDecision.onboarding() : route = _ProfileGateRoute.onboarding;
  const _ProfileGateDecision.home() : route = _ProfileGateRoute.home;
}

enum _LocGateState {
  loading,
  needsExplainer,
  needsPermission,
  blocked,
  granted,
}

class _PostAuthBootstrapShell extends StatefulWidget {
  const _PostAuthBootstrapShell({required this.uid});

  final String uid;

  @override
  State<_PostAuthBootstrapShell> createState() => _PostAuthBootstrapShellState();
}

class _PostAuthBootstrapShellState extends State<_PostAuthBootstrapShell> {
  static Future<void>? _globalBootFuture;
  static String _globalBootUid = "";

  bool _booted = false;
  bool _bootReady = false;
  _LocGateState _loc = _LocGateState.loading;
  Timer? _bootEscapeTimer;
  Timer? _grantedPulseTimer;
  bool _showGrantedPulse = false;

  @override
  void initState() {
    super.initState();
    _bootEscapeTimer = Timer(const Duration(seconds: 18), () {
      if (!mounted) return;

      if (_loc == _LocGateState.loading) {
        setState(() => _loc = _LocGateState.blocked);
        return;
      }

      if (_loc == _LocGateState.granted && !_bootReady) {
        setState(() => _bootReady = true);
      }
    });
    _initLocationGate();
  }

  @override
  void dispose() {
    _bootEscapeTimer?.cancel();
    _grantedPulseTimer?.cancel();
    super.dispose();
  }

  Future<void> _initLocationGate() async {
    try {
      bool granted = await LocationPermissions.instance
          .isGranted()
          .timeout(const Duration(seconds: 8), onTimeout: () => false);

      // On Samsung (and some other OEM) devices, Geolocator.isLocationServiceEnabled()
      // can return false during startup due to an AppOps race (MONITOR_LOCATION op
      // not yet registered). Retry once after a short delay before showing any
      // permission/blocked UI.
      if (!granted) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (!mounted) return;
        granted = await LocationPermissions.instance
            .isGranted()
            .timeout(const Duration(seconds: 8), onTimeout: () => false);
      }

      if (!mounted) return;

      if (granted) {
        setState(() => _loc = _LocGateState.granted);
        // ignore: discarded_futures
        _bootOnce();
        return;
      }

      final bool seenExplainer =
          await LocalFlags.instance
              .getBool(LocalFlags.kSeenLocationExplainer)
              .timeout(const Duration(seconds: 5), onTimeout: () => false) ??
              false;
      if (!mounted) return;

      setState(() => _loc = seenExplainer
          ? _LocGateState.needsPermission
          : _LocGateState.needsExplainer);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loc = _LocGateState.blocked);
    }
  }

  Future<void> _requestPermissionFromUserAction() async {
    bool granted = false;
    try {
      granted = await LocationPermissions.instance
          .requestFromUserAction()
          .timeout(const Duration(seconds: 10), onTimeout: () => false);
    } catch (_) {
      granted = false;
    }
    if (!mounted) return;

    if (!granted) {
      setState(() => _loc = _LocGateState.blocked);
      return;
    }

    setState(() => _loc = _LocGateState.granted);
    _grantedPulseTimer?.cancel();
    setState(() => _showGrantedPulse = true);
    _grantedPulseTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _showGrantedPulse = false);
    });
    // ignore: discarded_futures
    _bootOnce();
  }

  Future<void> _bootOnce() async {
    if (_booted) return;
    _booted = true;

    if (_globalBootUid != widget.uid) {
      _globalBootUid = widget.uid;
      _globalBootFuture = null;
    }

    if (_globalBootFuture == null) {
      _globalBootFuture = _runPostAuthBootstrap();
      // Never block home shell rendering on warm services.
      _globalBootFuture!.catchError((Object e, StackTrace st) {
        if (kDebugMode) debugPrint("[AuthGate] background post-auth bootstrap failed: $e");
      });
    }

    if (mounted && !_bootReady) {
      setState(() => _bootReady = true);
    }
  }

  Future<void> _runPostAuthBootstrap() async {
    // Force-refresh token so early Firestore requests are authed immediately (Android race fix).
    try {
      await FirebaseAuth.instance.currentUser
          ?.getIdToken(true)
          .timeout(const Duration(seconds: 6));
    } catch (e) {
      if (kDebugMode) debugPrint("[AuthGate] getIdToken refresh failed: $e");
    }

    // Apply referral attribution ASAP post-auth (warming signal).
    try {
      await ReferralAttribution.instance
          .applyIfPossible(uid: widget.uid)
          .timeout(const Duration(seconds: 6));
    } catch (e) {
      if (kDebugMode) debugPrint("[AuthGate] referral apply failed: $e");
    }

    Future<void>.delayed(const Duration(seconds: 6), () async {
      try {
        await PartyService.instance
            .syncReferralInPersonAutoJoins()
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        if (kDebugMode) debugPrint("[AuthGate] referral party auto-join sync failed: $e");
      }
    });

    try {
      await UserSettingsService.instance
          .ensureLoaded()
          .timeout(const Duration(seconds: 5));
      final settingsSvc = UserSettingsService.instance;
        final entitlements = await MonetizationService.instance
          .getEntitlementsMap(uid: widget.uid)
          .timeout(const Duration(seconds: 6), onTimeout: () => const <String, dynamic>{});
        final highRadiusUnlocked = entitlements["highRadiusUnlocked"] == true;
        final singleKeywordUnlocked = entitlements["singleKeywordMatchModeUnlocked"] == true;
        final reciprocalUnlocked = entitlements["reciprocalKeywordMatchModeUnlocked"] == true;
        final keywordChainUnlocked = entitlements["keywordChainMatchModeUnlocked"] == true;
      settingsSvc.setHighRadiusUnlocked(highRadiusUnlocked);
        settingsSvc.setSingleKeywordMatchUnlocked(singleKeywordUnlocked);
        settingsSvc.setReciprocalMatchUnlocked(reciprocalUnlocked);
        settingsSvc.setKeywordChainUnlocked(keywordChainUnlocked);

      final current = settingsSvc.current.matchDiscovery;
      final maxAllowed = MatchDiscoverySettings.allowedMaxRadiusMiles(
        highRadiusUnlocked: current.highRadiusUnlocked,
        businessOnly: current.businessOnly,
        modeKind: MatchingModeKind.normal,
        normalMode: NormalMatchMode.passive,
      );
      final defaults = current.copyWith(
        modeKind: MatchingModeKind.normal,
        normalMode: NormalMatchMode.passive,
        radiusMiles: maxAllowed,
      );
      settingsSvc.updateMatchDiscovery(defaults);

        await PushNotifications.instance
          .initForUser(widget.uid)
          .timeout(const Duration(seconds: 8));

      // Presence: start live writing after location is granted.
      final bool ok =
          await PresenceWriter.instance
              .startLive(reason: "post_auth")
              .timeout(const Duration(seconds: 8), onTimeout: () => false);

      // Nearby bootstrap is now started on-demand when Nearby screen opens.

      if (kDebugMode) {
        debugPrint(
          "[AuthGate] post-auth boot complete (presenceLive=$ok) - nearby bootstrap started",
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint("[AuthGate] post-auth bootstrap error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_loc) {
      case _LocGateState.loading:
        return const _GateLoadingScreen(message: "Checking location permissions...");

      case _LocGateState.needsExplainer:
        return LocationPermissionExplainerScreen(
          onContinue: () async {
            await LocalFlags.instance
                .setBool(LocalFlags.kSeenLocationExplainer, true);
            if (!mounted) return;
            setState(() => _loc = _LocGateState.needsPermission);
          },
          onSkip: () {
            setState(() => _loc = _LocGateState.blocked);
          },
        );

      case _LocGateState.needsPermission:
        return LocationPermissionExplainerScreen(
          mode: LocationExplainerMode.permissionPromptContext,
          onContinue: _requestPermissionFromUserAction,
          onSkip: () {
            setState(() => _loc = _LocGateState.blocked);
          },
        );

      case _LocGateState.blocked:
        return LocationPermissionBlockedScreen(
          onRetry: _requestPermissionFromUserAction,
          onRecheck: _initLocationGate,
        );

      case _LocGateState.granted:
        if (!_bootReady) {
          return const _GateLoadingScreen(
            message: "Stabilizing app services for smooth startup...",
          );
        }
        return _GrantedLocationShell(
          showPulse: _showGrantedPulse,
          child: const HomeRootShell(),
        );
    }
  }
}

class _GrantedLocationShell extends StatelessWidget {
  const _GrantedLocationShell({
    required this.showPulse,
    required this.child,
  });

  final bool showPulse;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = ProxMotion.prefersReducedMotion(context);

    return Stack(
      children: [
        child,
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: SafeArea(
            bottom: false,
            child: IgnorePointer(
              child: AnimatedSwitcher(
                duration: ProxMotion.dur(context, ProxMotion.kFast),
                switchInCurve: ProxMotion.curve(context),
                switchOutCurve: ProxMotion.curve(context),
                transitionBuilder: (w, a) {
                  if (reduce) {
                    return FadeTransition(opacity: a, child: w);
                  }
                  return FadeTransition(
                    opacity: a,
                    child: ScaleTransition(scale: a, child: w),
                  );
                },
                child: showPulse
                    ? Center(
                        key: const ValueKey<String>("grant_pulse"),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 320),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: cs.primary.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle, color: cs.primary),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  "Location enabled",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: cs.onPrimaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(
                        key: ValueKey<String>("grant_pulse_off"),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

List<String> _readStringList(dynamic raw) {
  if (raw is List) {
    return raw
        .whereType<dynamic>()
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

List<String> _keywordsFromAllShapes(Map<String, dynamic> data, List<String> keys) {
  for (final k in keys) {
    final v = data[k];
    final list = _readStringList(v);
    if (list.isNotEmpty) return list;
  }
  return const <String>[];
}

List<String> _keywordsFromKeywordsMap(Map<String, dynamic> data, List<String> keys) {
  final dynamic raw = data["keywords"];
  if (raw is! Map) return const <String>[];
  final Map<String, dynamic> m = Map<String, dynamic>.from(raw);

  for (final k in keys) {
    final list = _readStringList(m[k]);
    if (list.isNotEmpty) return list;
  }
  return const <String>[];
}

bool _isProfileComplete(Map<String, dynamic> data) {
  final String name =
      (data["displayName"] as String? ?? data["name"] as String? ?? "").trim();

  final String selfie =
      ((data["selfieUrl"] as String?) ?? (data["photoUrl"] as String?) ?? "")
          .trim();

  // Searching For
  final List<String> searching = _keywordsFromAllShapes(
        data,
        const <String>[
          "searchingForKeywords",
          "searchingFor",
          "SearchingFor",
          "Searching For",
        ],
      ).isNotEmpty
      ? _keywordsFromAllShapes(
          data,
          const <String>[
            "searchingForKeywords",
            "searchingFor",
            "SearchingFor",
            "Searching For",
          ],
        )
      : _keywordsFromKeywordsMap(
          data,
          const <String>[
            "Searching For",
            "SearchingFor",
            "searchingFor",
            "searching_for",
          ],
        );

  // Can Provide
  final List<String> providing = _keywordsFromAllShapes(
        data,
        const <String>[
          "canProvideKeywords",
          "canProvide",
          "CanProvide",
          "Can Provide",
        ],
      ).isNotEmpty
      ? _keywordsFromAllShapes(
          data,
          const <String>[
            "canProvideKeywords",
            "canProvide",
            "CanProvide",
            "Can Provide",
          ],
        )
      : _keywordsFromKeywordsMap(
          data,
          const <String>[
            "Can Provide",
            "CanProvide",
            "canProvide",
            "can_provide",
          ],
        );

  final bool hasName = name.isNotEmpty;
  final bool hasSelfie = selfie.isNotEmpty;
  final bool hasSearching = searching.isNotEmpty;
  final bool hasProviding = providing.isNotEmpty;

  return hasName && hasSelfie && hasSearching && hasProviding;
}

class _SplashLoading extends StatelessWidget {
  const _SplashLoading();

  @override
  Widget build(BuildContext context) {
    return const _GateLoadingScreen(message: "Preparing your account...");
  }
}

class _GateLoadingScreen extends StatelessWidget {
  const _GateLoadingScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.8),
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
