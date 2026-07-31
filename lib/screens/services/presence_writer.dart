import "dart:async";
import "dart:math" as math;

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";
import "package:geolocator/geolocator.dart";

import "package:prox/services/app_lifecycle_service.dart";
import "package:prox/services/app_build_info_service.dart";
import "package:prox/services/ime_visibility_service.dart";
import "package:prox/services/motion_classifier.dart";
import "package:prox/services/ttl/ttl_policy.dart";
import "package:prox/services/user_settings_service.dart";

class MotionSnapshot {
  final double lat;
  final double lng;
  final DateTime ts;
  final MotionState motion;
  final double speedMps;

  const MotionSnapshot({
    required this.lat,
    required this.lng,
    required this.ts,
    required this.motion,
    required this.speedMps,
  });
}

/// PresenceWriter
///
/// Battery-first presence updates:
/// - Uses burst-based GPS (one-shot fixes on a schedule), not a continuous stream.
/// - Uses a "power budget" mindset: cap writes, cap GPS-on time, and measure it.
/// - Escalates to high accuracy briefly for meetups / movement; drops to balanced/low when stationary.
/// - Writes only the minimal presence current doc: geopoint + ts + expiresAt.
///
/// STORE-SAFE RULE:
/// PresenceWriter never calls requestPermission(). Permission prompts must be driven by
/// explicit user flows (LocationGate disclosure, meetup start, etc.).
class PresenceWriter {
  PresenceWriter._() {
    AppLifecycleService.instance.ensureStarted();
    AppLifecycleService.instance.addListener(_onLifecycle);
    ImeVisibilityService.instance.ensureStarted();
    ImeVisibilityService.instance.addListener(_onImeChanged);
  }

  static final PresenceWriter instance = PresenceWriter._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? _cachedAppVersion;

  final MotionClassifier _motion = MotionClassifier();

  MotionState _currentMotion = MotionState.unknown;
  MotionState get currentMotion => _currentMotion;

  bool _liveRunning = false;
  bool get isRunning => _liveRunning;

  int _liveClients = 0;

  // Core knobs
  Duration throttle = const Duration(seconds: 20);
  double movementGateMeters = 30.0;

  // Foreground interaction writes
  Duration interactionMinGap = const Duration(seconds: 90);
  DateTime? _lastInteractionWrite;

  Duration startupSeedMinGap = const Duration(seconds: 20);

  // Debounce + max age (foreground)
  Duration debounce = const Duration(seconds: 3);
  Duration maxAgeFlush = const Duration(seconds: 45);

  // Meetup mode = tighter loop
  Duration meetupDebounce = const Duration(seconds: 1);
  Duration meetupMaxAgeFlush = const Duration(seconds: 20);

  int _meetupModeClients = 0;
  bool get isMeetupMode => _meetupModeClients > 0;

  Timer? _debounceTimer;
  Timer? _maxAgeTimer;

  // Burst GPS timer (instead of continuous getPositionStream)
  Timer? _pulseTimer;

  double? _pendingLat;
  double? _pendingLng;
  bool _pendingForce = false;
  bool _pendingCached = false;

  DateTime? _lastWrite;
  DateTime? _writeSuppressedUntil;

  double? _lastLat;
  double? _lastLng;
  DateTime? _lastTs;

  double? _lastWriteLat;
  double? _lastWriteLng;

  bool _pausedForBackground = false;
  bool _pausedForIme = false;
  bool _pausedForCriticalUi = false;
  bool _startingPulse = false;

  final StreamController<MotionSnapshot> _motionController =
      StreamController<MotionSnapshot>.broadcast();
  Stream<MotionSnapshot> get motionStream => _motionController.stream;

  Duration presenceTtl = TTLPolicy.presenceCurrent;

  // Accept last-known fixes up to this age when live fixes time out.
  static const Duration _lastKnownMaxAge = Duration(minutes: 15);

  // -----------------------------
  // Power-budget metrics
  // -----------------------------
  int _gpsOnMs = 0;
  int _fixCount = 0;
  final List<int> _ttffMs = <int>[];

  int _writes = 0;
  DateTime _metricsWindowStart = DateTime.now();

  void _rollMetricsWindowIfNeeded() {
    final now = DateTime.now();
    if (now.difference(_metricsWindowStart) >= const Duration(hours: 1)) {
      _gpsOnMs = 0;
      _fixCount = 0;
      _ttffMs.clear();
      _writes = 0;
      _metricsWindowStart = now;
    }
  }

  int get gpsOnMsThisWindow {
    _rollMetricsWindowIfNeeded();
    return _gpsOnMs;
  }

  int get fixesThisWindow {
    _rollMetricsWindowIfNeeded();
    return _fixCount;
  }

  int get writesThisWindow {
    _rollMetricsWindowIfNeeded();
    return _writes;
  }

  int get ttffP95Ms {
    _rollMetricsWindowIfNeeded();
    if (_ttffMs.isEmpty) return 0;
    final sorted = List<int>.from(_ttffMs)..sort();
    final idx = ((sorted.length - 1) * 0.95).round().clamp(0, sorted.length - 1);
    return sorted[idx];
  }

  Map<String, Object?> debugMetrics() {
    _rollMetricsWindowIfNeeded();
    return <String, Object?>{
      "gpsOnSecondsPerHour": (gpsOnMsThisWindow / 1000.0).toStringAsFixed(1),
      "fixesPerHour": fixesThisWindow,
      "writesPerHour": writesThisWindow,
      "ttffP95ms": ttffP95Ms,
      "motion": _currentMotion.name,
      "meetupMode": isMeetupMode,
      "running": _liveRunning,
      "pausedBg": _pausedForBackground,
    };
  }

  // -----------------------------
  // Public API
  // -----------------------------
  Future<bool> start() => startLive(reason: "start()");

  Future<void> forceWrite({String reason = "forceWrite"}) async {
    await flushNow(reason: reason);
  }

  Future<bool> startLive({String reason = "live"}) async {
    _liveClients += 1;

    if (_liveRunning) return true;

    final bool enabled = await _isServiceEnabledWithRetry();
    if (!enabled) {
      _log("[PresenceWriter] startLive location services disabled reason=$reason");
      _liveClients = math.max(0, _liveClients - 1);
      return false;
    }

    _liveRunning = true;
    _pausedForBackground = false;

    // Best-effort seed write
    // ignore: unawaited_futures
    flushNow(reason: "seed_startLive:$reason");

    _startPulse();
    _scheduleMaxAgeFlush();
    return true;
  }

  Future<void> stopLive({String reason = "live"}) async {
    if (_liveClients > 0) _liveClients -= 1;

    if (_liveClients <= 0) {
      _liveClients = 0;
      _liveRunning = false;
      _pausedForBackground = false;
      _cancelTimers();
      _stopPulse();
    }
  }

  Future<void> beginMeetupMode({String reason = "meetup"}) async {
    _meetupModeClients += 1;
    // ignore: unawaited_futures
    flushNow(reason: "meetup_begin:$reason");
    _startPulse();
    _scheduleMaxAgeFlush();
  }

  Future<void> endMeetupMode({String reason = "meetup"}) async {
    if (_meetupModeClients > 0) _meetupModeClients -= 1;
    _startPulse(); // adjust cadence
    _scheduleMaxAgeFlush();
  }

  Future<void> notifyForegroundInteraction({String reason = "foreground"}) async {
    await _maybeInteractionWrite(reason: "fg:$reason");
  }

  Future<void> notifyChatEvent({String reason = "chat"}) async {
    await _maybeInteractionWrite(reason: "chat:$reason");
  }

  Future<void> notifyMeetupEvent({String reason = "meetup"}) async {
    await _maybeInteractionWrite(reason: "meetup:$reason");
  }

  void beginCriticalUiSection({String reason = "critical_ui"}) {
    if (_pausedForCriticalUi) return;
    _pausedForCriticalUi = true;
    _log("[PresenceWriter] critical UI pause enabled reason=$reason");
    _stopPulse();
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  void endCriticalUiSection({String reason = "critical_ui"}) {
    if (!_pausedForCriticalUi) return;
    _pausedForCriticalUi = false;
    _log("[PresenceWriter] critical UI pause disabled reason=$reason");
    if (_liveRunning && !_pausedForBackground && !_pausedForIme) {
      _startPulse();
      _scheduleMaxAgeFlush();
    }
  }

  bool _isStartupSeedReason(String reason) {
    final r = reason.toLowerCase();
    return r.contains("seed") || r.contains("post_auth") || r.contains("bootstrap");
  }

  bool _skipAsDuplicateStartupSeed(String reason) {
    if (!_isStartupSeedReason(reason)) return false;
    if (_lastWrite == null) return false;
    return DateTime.now().difference(_lastWrite!) < startupSeedMinGap;
  }

  // -----------------------------
  // Internals
  // -----------------------------
  Future<void> _maybeInteractionWrite({required String reason}) async {
    final now = DateTime.now();
    if (_lastInteractionWrite != null &&
        now.difference(_lastInteractionWrite!) < interactionMinGap) {
      return;
    }
    _lastInteractionWrite = now;
    await flushNow(reason: "interaction:$reason");
  }

  Future<bool> _isServiceEnabledWithRetry() async {
    try {
      final bool enabled = await Geolocator.isLocationServiceEnabled();
      if (enabled) return true;
      await Future<void>.delayed(const Duration(seconds: 2));
      return await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      return false;
    }
  }

  Duration _effectiveThrottle({required double speedMps}) {
    final base = throttle;

    if (speedMps >= 0.0 && speedMps < 0.20) {
      return base < const Duration(seconds: 45) ? const Duration(seconds: 45) : base;
    }

    if (speedMps >= 8.0) return const Duration(seconds: 8);
    if (speedMps >= 1.2) return const Duration(seconds: 15);

    return base;
  }

  Duration get _effectiveDebounce => isMeetupMode ? meetupDebounce : debounce;
  Duration get _effectiveMaxAgeFlush => isMeetupMode ? meetupMaxAgeFlush : maxAgeFlush;

  Duration _pulseIntervalFor(MotionState motion) {
    if (isMeetupMode) return const Duration(seconds: 6);
    if (motion == MotionState.stationary) return const Duration(seconds: 45);
    if (motion == MotionState.unknown) return const Duration(seconds: 25);
    return const Duration(seconds: 15);
  }

  LocationAccuracy _accuracyFor(MotionState motion) {
    if (isMeetupMode) return LocationAccuracy.high;
    if (motion == MotionState.stationary) return LocationAccuracy.low;
    return LocationAccuracy.medium;
  }

  Duration _timeLimitFor(MotionState motion) {
    if (isMeetupMode) return const Duration(seconds: 8);
    if (motion == MotionState.stationary) return const Duration(seconds: 8);
    return const Duration(seconds: 10);
  }

  bool _isAccuracyAcceptable({required Position pos, required bool meetupMode}) {
    final meters = pos.accuracy;
    if (!meters.isFinite || meters <= 0) return true;
    // Keep meetup mode stricter while tolerating noisier passive fixes.
    return meetupMode ? meters <= 150 : meters <= 300;
  }

  void _startPulse() {
    if (!_liveRunning) return;
    if (_pausedForBackground) return;
    if (_pausedForIme) return;
    if (_pausedForCriticalUi) return;

    if (_startingPulse) return;
    _startingPulse = true;

    try {
      _pulseTimer?.cancel();

      final interval = _pulseIntervalFor(_currentMotion);
      _pulseTimer = Timer.periodic(interval, (_) {
        // ignore: unawaited_futures
        _pulseOnce(reason: "timer");
      });

      // ignore: unawaited_futures
      _pulseOnce(reason: "start");
    } finally {
      _startingPulse = false;
    }
  }

  void _stopPulse() {
    _pulseTimer?.cancel();
    _pulseTimer = null;
  }

  void _onLifecycle() {
    if (!_liveRunning) return;

    final bool isForeground = AppLifecycleService.instance.isForeground;

    if (!isForeground && !_pausedForBackground) {
      _pausedForBackground = true;
      // ignore: unawaited_futures
      flushNow(reason: "lifecycle_bg");
      _stopPulse();
      return;
    }

    if (isForeground && _pausedForBackground) {
      _pausedForBackground = false;
      if (!_pausedForIme && !_pausedForCriticalUi) {
        _startPulse();
      }
      // ignore: unawaited_futures
      flushNow(reason: "lifecycle_fg");
      _scheduleMaxAgeFlush();
    }
  }

  void _onImeChanged() {
    if (!_liveRunning) return;

    final bool visible = ImeVisibilityService.instance.isVisible;
    if (visible) {
      if (_pausedForIme) return;
      _pausedForIme = true;
      _stopPulse();
      return;
    }

    if (!_pausedForIme) return;
    _pausedForIme = false;
    if (!_pausedForBackground && !_pausedForCriticalUi) {
      _startPulse();
      _scheduleMaxAgeFlush();
    }
  }

  Future<void> _pulseOnce({required String reason}) async {
    if (!_liveRunning) return;
    if (_pausedForBackground) return;
    if (_pausedForIme) return;
    if (_pausedForCriticalUi) return;
    if (ImeVisibilityService.instance.isVisible) {
      _scheduleMaxAgeFlush();
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      _log("[PresenceWriter] pulse skipped no user reason=$reason");
      return;
    }

    final bool enabled = await _isServiceEnabledWithRetry();
    if (!enabled) {
      _log("[PresenceWriter] pulse skipped location services disabled reason=$reason");
      return;
    }

    _rollMetricsWindowIfNeeded();

    final motion = _currentMotion;
    final acc = _accuracyFor(motion);
    final tlim = _timeLimitFor(motion);

    final sw = Stopwatch()..start();
    final result = await _getPositionWithFallback(
      accuracy: acc,
      timeLimit: tlim,
    );
    final Position? pos = result.pos;
    final bool usedCached = result.cached;

    try {
      // no-op: result already fetched
    } finally {
      sw.stop();
      final elapsed = sw.elapsedMilliseconds;
      _gpsOnMs += elapsed.clamp(0, 60000);
      _ttffMs.add(elapsed.clamp(0, 60000));
    }

    if (pos == null) return;
    if (!_isAccuracyAcceptable(pos: pos, meetupMode: isMeetupMode)) {
      _log(
        "[PresenceWriter] pulse skipped poor accuracy=${pos.accuracy.toStringAsFixed(1)}m reason=$reason",
      );
      _scheduleMaxAgeFlush();
      _startPulse();
      return;
    }

    _fixCount += 1;

    final now = DateTime.now();

    _motion.addSample(lat: pos.latitude, lng: pos.longitude, ts: now);
    _currentMotion = _motion.currentState;

    double speedMps = 0.0;
    if (_lastLat != null && _lastLng != null && _lastTs != null) {
      final int dtSeconds = now.difference(_lastTs!).inSeconds;
      if (dtSeconds > 0) {
        final double distanceMeters = _distanceMeters(
          _lastLat!,
          _lastLng!,
          pos.latitude,
          pos.longitude,
        );
        speedMps = distanceMeters / dtSeconds;
      }
    }

    _lastLat = pos.latitude;
    _lastLng = pos.longitude;
    _lastTs = now;

    if (!_motionController.isClosed) {
      _motionController.add(
        MotionSnapshot(
          lat: pos.latitude,
          lng: pos.longitude,
          ts: now,
          motion: _currentMotion,
          speedMps: speedMps,
        ),
      );
    }

    final Duration effThrottle = _effectiveThrottle(speedMps: speedMps);
    if (_lastWrite != null && now.difference(_lastWrite!) < effThrottle) {
      _scheduleMaxAgeFlush();
      _startPulse();
      return;
    }

    bool passedMovementGate = true;
    if (_lastWriteLat != null && _lastWriteLng != null) {
      final double movedSinceWrite = _distanceMeters(
        _lastWriteLat!,
        _lastWriteLng!,
        pos.latitude,
        pos.longitude,
      );
      if (movedSinceWrite < movementGateMeters) {
        passedMovementGate = false;
      }
    }

    final bool dueToMaxAge = _lastWrite == null ||
        now.difference(_lastWrite!) >= _effectiveMaxAgeFlush;

    if (!passedMovementGate && !dueToMaxAge) {
      _scheduleMaxAgeFlush();
      _startPulse();
      return;
    }

    _requestWrite(
      uid: user.uid,
      lat: pos.latitude,
      lon: pos.longitude,
      force: dueToMaxAge,
      cached: usedCached,
    );
    _startPulse();
  }

  void _cancelTimers() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _maxAgeTimer?.cancel();
    _maxAgeTimer = null;

    _stopPulse();

    _pendingLat = null;
    _pendingLng = null;
    _pendingForce = false;
    _pendingCached = false;
  }

  void _scheduleMaxAgeFlush() {
    if (!_liveRunning) return;

    final Duration maxAge = _effectiveMaxAgeFlush;

    final DateTime now = DateTime.now();
    final DateTime last = _lastWrite ?? now.subtract(maxAge);

    final Duration untilDue = maxAge - now.difference(last);
    final Duration delay = untilDue.isNegative ? Duration.zero : untilDue;

    _maxAgeTimer?.cancel();
    _maxAgeTimer = Timer(delay, () {
      // ignore: unawaited_futures
      flushNow(reason: "timer_max_age");
    });
  }

  void _requestWrite({
    required String uid,
    required double lat,
    required double lon,
    bool force = false,
    bool cached = false,
  }) {
    _pendingLat = lat;
    _pendingLng = lon;
    _pendingForce = _pendingForce || force;
    _pendingCached = _pendingCached || cached;

    if (cached) {
      _pendingForce = true; // write cached locations immediately
    }

    final Duration d = _effectiveDebounce;

    if (_pendingForce || d <= Duration.zero) {
      // ignore: unawaited_futures
      _flushPending();
      return;
    }

    if (_debounceTimer != null && _debounceTimer!.isActive) return;

    _debounceTimer = Timer(d, () {
      // ignore: unawaited_futures
      _flushPending();
    });
  }

  Future<void> _flushPending() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;

    final user = _auth.currentUser;
    if (user == null) return;
    if (!_liveRunning) return;

    final double? lat = _pendingLat;
    final double? lon = _pendingLng;

    _pendingLat = null;
    _pendingLng = null;
    final bool cached = _pendingCached;
    _pendingForce = false;
    _pendingCached = false;

    if (lat == null || lon == null) return;

    if (_isWriteSuppressed()) {
      _scheduleMaxAgeFlush();
      return;
    }

    final bool wrote = await _writePresence(
      uid: user.uid,
      lat: lat,
      lon: lon,
      cached: cached,
    );
    if (wrote) {
      _markWrote(DateTime.now(), lat, lon);
    }
    _scheduleMaxAgeFlush();
  }

  void _markWrote(DateTime now, double lat, double lon) {
    _lastWrite = now;
    _lastWriteLat = lat;
    _lastWriteLng = lon;
    _writes += 1;
  }

  Future<void> flushNow({String reason = "flush"}) async {
    if (_pausedForCriticalUi) {
      _log("[PresenceWriter] flush skipped critical UI pause reason=$reason");
      return;
    }

    if (_skipAsDuplicateStartupSeed(reason)) {
      _log("[PresenceWriter] flush skipped duplicate startup seed reason=$reason");
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      _log("[PresenceWriter] flush skipped no user reason=$reason");
      return;
    }
    if (_isWriteSuppressed()) {
      _log("[PresenceWriter] flush skipped suppressed reason=$reason");
      return;
    }

    final bool enabled = await _isServiceEnabledWithRetry();
    if (!enabled) {
      _log("[PresenceWriter] flush skipped location services disabled reason=$reason");
      return;
    }

    if (_lastLat != null && _lastLng != null) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _pendingLat = null;
      _pendingLng = null;
      _pendingForce = false;

      final bool wrote = await _writePresence(
        uid: user.uid,
        lat: _lastLat!,
        lon: _lastLng!,
      );
      if (wrote) {
        _markWrote(DateTime.now(), _lastLat!, _lastLng!);
      }
      _scheduleMaxAgeFlush();
      return;
    }

    await writeOneShot(reason: "flush_fallback:$reason");
  }

  Future<bool> writeOneShot({
    String reason = "one_shot",
    LocationAccuracy accuracy = LocationAccuracy.medium,
  }) async {
    if (_pausedForCriticalUi) {
      _log("[PresenceWriter] oneShot skipped critical UI pause reason=$reason");
      return false;
    }

    if (_skipAsDuplicateStartupSeed(reason)) {
      _log("[PresenceWriter] oneShot skipped duplicate startup seed reason=$reason");
      return false;
    }

    if (_isWriteSuppressed()) {
      _log("[PresenceWriter] oneShot skipped suppressed reason=$reason");
      return false;
    }

    final bool enabled = await _isServiceEnabledWithRetry();
    if (!enabled) {
      _log("[PresenceWriter] oneShot skipped location services disabled reason=$reason");
      return false;
    }

    final user = _auth.currentUser;
    if (user == null) {
      _log("[PresenceWriter] oneShot skipped no user reason=$reason");
      return false;
    }

    final sw = Stopwatch()..start();
    try {
      final result = await _getPositionWithFallback(
        accuracy: accuracy,
        timeLimit: const Duration(seconds: 10),
      );
      final Position? pos = result.pos;
      final bool usedCached = result.cached;

      if (pos == null) {
        _log("[PresenceWriter] oneShot no position reason=$reason");
        return false;
      }
      if (!_isAccuracyAcceptable(pos: pos, meetupMode: isMeetupMode)) {
        _log(
          "[PresenceWriter] oneShot skipped poor accuracy=${pos.accuracy.toStringAsFixed(1)}m reason=$reason",
        );
        return false;
      }

      sw.stop();
      _rollMetricsWindowIfNeeded();
      _gpsOnMs += sw.elapsedMilliseconds.clamp(0, 60000);
      _ttffMs.add(sw.elapsedMilliseconds.clamp(0, 60000));
      _fixCount += 1;

      _lastLat = pos.latitude;
      _lastLng = pos.longitude;
      _lastTs = DateTime.now();

      final bool wrote = await _writePresence(
        uid: user.uid,
        lat: pos.latitude,
        lon: pos.longitude,
        cached: usedCached,
      );
      if (!wrote) return false;

      _markWrote(DateTime.now(), pos.latitude, pos.longitude);
      _scheduleMaxAgeFlush();
      _log("[PresenceWriter] oneShot wrote uid=${user.uid} cached=$usedCached reason=$reason");
      return true;
    } catch (_) {
      sw.stop();
      _rollMetricsWindowIfNeeded();
      _gpsOnMs += sw.elapsedMilliseconds.clamp(0, 60000);
      _ttffMs.add(sw.elapsedMilliseconds.clamp(0, 60000));
      return false;
    }
  }

  Future<bool> _writePresence({
    required String uid,
    required double lat,
    required double lon,
    bool cached = false,
  }) async {
    final demoAdjusted = await _applyDemoNearbyLocationOverride(
      uid: uid,
      lat: lat,
      lon: lon,
    );

    final ref = _db.doc("users/$uid/presence/current");
    try {
      final String appVersion = await _appVersionLabel();
      await ref.set(
        <String, Object?>{
          "kind": "current",
          "geopoint": GeoPoint(demoAdjusted.lat, demoAdjusted.lon),
          "appVersion": appVersion,
          "ts": FieldValue.serverTimestamp(),
          "expiresAt": TTLPolicy.expiresAtFromNow(presenceTtl),
          if (cached) "cached": true,
        },
        SetOptions(merge: true),
      );
      _log("[PresenceWriter] write success uid=$uid cached=$cached");
      return true;
    } on FirebaseException catch (e) {
      if (e.code == "permission-denied" || e.code == "unauthenticated") {
        // Auth/rules races can happen briefly during startup; pause writes to avoid
        // noisy retry storms and let auth refresh settle.
        await _refreshIdTokenBestEffort();
        _suppressWritesFor(const Duration(seconds: 30));
        _log(
          "[PresenceWriter] write skipped (${e.code}) uid=$uid; suppressing for 30s",
        );
        return false;
      }

      _log("[PresenceWriter] write failed uid=$uid code=${e.code}: ${e.message}");
      return false;
    } catch (e) {
      _log("[PresenceWriter] write failed uid=$uid: $e");
      return false;
    }
  }

  Future<String> _appVersionLabel() async {
    final cached = _cachedAppVersion;
    if (cached != null && cached.trim().isNotEmpty) {
      return cached;
    }

    final value = await AppBuildInfoService.instance.fullVersion();
    _cachedAppVersion = value;
    return value;
  }

  Future<({double lat, double lon})> _applyDemoNearbyLocationOverride({
    required String uid,
    required double lat,
    required double lon,
  }) async {
    try {
      await UserSettingsService.instance.ensureLoaded();
      final settings = UserSettingsService.instance.current;
      if (!settings.demoModeEnabled || !settings.demoSimulatedNearbyLocationEnabled) {
        return (lat: lat, lon: lon);
      }

      final miles = settings.demoSimulatedNearbyOffsetMiles.clamp(0.0, 1.0).toDouble();
      if (miles <= 0.0) return (lat: lat, lon: lon);

      final bearingDeg = _stableBearingForUid(uid);
      return _offsetLatLonByMiles(
        lat: lat,
        lon: lon,
        miles: miles,
        bearingDeg: bearingDeg,
      );
    } catch (_) {
      return (lat: lat, lon: lon);
    }
  }

  double _stableBearingForUid(String uid) {
    int hash = 0;
    for (final c in uid.codeUnits) {
      hash = ((hash * 31) + c) & 0x7fffffff;
    }
    return (hash % 360).toDouble();
  }

  ({double lat, double lon}) _offsetLatLonByMiles({
    required double lat,
    required double lon,
    required double miles,
    required double bearingDeg,
  }) {
    const double earthRadiusM = 6371008.8;
    final distanceM = miles * 1609.344;

    final lat1 = lat * math.pi / 180.0;
    final lon1 = lon * math.pi / 180.0;
    final bearing = bearingDeg * math.pi / 180.0;
    final angularDistance = distanceM / earthRadiusM;

    final sinLat1 = math.sin(lat1);
    final cosLat1 = math.cos(lat1);
    final sinAngular = math.sin(angularDistance);
    final cosAngular = math.cos(angularDistance);

    final sinLat2 = sinLat1 * cosAngular + cosLat1 * sinAngular * math.cos(bearing);
    final lat2 = math.asin(sinLat2.clamp(-1.0, 1.0));

    final y = math.sin(bearing) * sinAngular * cosLat1;
    final x = cosAngular - sinLat1 * sinLat2;
    final lon2 = lon1 + math.atan2(y, x);

    double outLon = lon2 * 180.0 / math.pi;
    outLon = ((outLon + 540.0) % 360.0) - 180.0;

    return (
      lat: (lat2 * 180.0 / math.pi).clamp(-90.0, 90.0),
      lon: outLon,
    );
  }

  bool _isWriteSuppressed() {
    final until = _writeSuppressedUntil;
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _writeSuppressedUntil = null;
      return false;
    }
    return true;
  }

  void _suppressWritesFor(Duration duration) {
    final now = DateTime.now();
    _writeSuppressedUntil = now.add(duration);
    // Prevent immediate max-age flush loops while suppressed.
    _lastWrite = now;
  }

  Future<void> _refreshIdTokenBestEffort() async {
    try {
      await _auth.currentUser?.getIdToken(true);
    } catch (_) {
      // Best effort only.
    }
  }

  Future<Position?> _getLastKnownIfFresh() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) return null;
      final age = DateTime.now().difference(last.timestamp);
      if (age > _lastKnownMaxAge) return null;
      return last;
    } catch (_) {
      return null;
    }
  }

  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000.0;
    double degToRad(double deg) => deg * (math.pi / 180.0);

    final double dLat = degToRad(lat2 - lat1);
    final double dLon = degToRad(lon2 - lon1);

    final double rLat1 = degToRad(lat1);
    final double rLat2 = degToRad(lat2);

    final double sinLat = math.sin(dLat / 2);
    final double sinLon = math.sin(dLon / 2);

    final double a = sinLat * sinLat +
        sinLon * sinLon * math.cos(rLat1) * math.cos(rLat2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

    Future<_PositionResult> _getPositionWithFallback({
    required LocationAccuracy accuracy,
    required Duration timeLimit,
  }) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          distanceFilter: 0,
          timeLimit: timeLimit,
        ),
      );
      return _PositionResult(pos: pos, cached: false);
    } catch (_) {}

    final last = await _getLastKnownIfFresh();
    if (last != null) return _PositionResult(pos: last, cached: true);

    return const _PositionResult(pos: null, cached: false);
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}

class _PositionResult {
  final Position? pos;
  final bool cached;

  const _PositionResult({
    required this.pos,
    required this.cached,
  });
}
