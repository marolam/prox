import "dart:async";
import "dart:math" as math;
import "dart:ui";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:flutter/foundation.dart" show setEquals;

import "package:prox/models/user_settings.dart";
import "package:prox/screens/discovery/matching_mode_screen.dart";
import "package:prox/screens/treasure_hunt/treasure_hunt_screen.dart";
import "package:prox/services/chat/chat_gate_service.dart";
import "package:prox/services/chat/chat_thread_service.dart";
import "package:prox/services/chat/unread_counter_service.dart";
import "package:prox/services/geoquery_service.dart";
import "package:prox/services/location_privacy_service.dart";
import "package:prox/services/matching/match_candidate.dart";
import "package:prox/services/matching/active_mode_policy_service.dart";
import "package:prox/services/matching/matching_mode_service.dart";
import "package:prox/services/matching/matching_runtime_service.dart";
import "package:prox/services/matching/prox_circle_interaction_policy.dart";
import "package:prox/services/matching/match_pipeline.dart";
import "package:prox/services/meetup_service.dart";
import "package:prox/services/party_mode_service.dart";
import "package:prox/services/party_service.dart";
import "package:prox/services/presence_writer.dart";
import "package:prox/services/runtime_diagnostics_service.dart";
import "package:prox/services/user_profile_service.dart";
import "package:prox/services/user_settings_service.dart";
import "package:prox/services/simple_mode/simple_mode_policy.dart";
import "package:prox/utils/presentation/prox_distance_format.dart";
import "package:prox/utils/presentation/prox_identity_policy.dart";
import "package:prox/widgets/location_issue_banner.dart";
import "package:prox/widgets/match_found_sheet.dart";
import "package:prox/widgets/prox_background.dart";
import "package:prox/widgets/prox_glass.dart";
import "package:prox/widgets/prox_logo_mark.dart";

class MatchInboxScreen extends StatefulWidget {
  const MatchInboxScreen({super.key});

  @override
  State<MatchInboxScreen> createState() => _MatchInboxScreenState();
}

class _LockedSearchRow extends StatelessWidget {
  const _LockedSearchRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          const Icon(Icons.lock, size: 14),
        ],
      ),
    );
  }
}

class _MatchInboxScreenState extends State<MatchInboxScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // Guardrail: this anchor marks the Nearby Prox Circle activation control.
  // Keep this widget in the tree; tests enforce this key's presence.
  static const Key _kNearbyProxCircleAnchorKey = ValueKey<String>(
    "nearby_prox_circle_anchor",
  );

  bool _opening = false;
  String _openingUid = "";
  bool _showingActiveConfirmation = false;

  static const int _newUserWindowDays = 7;

  static const Duration _kHoldToActivateDuration = Duration(seconds: 3);
  static const Duration _kStartupTapOffWindow = Duration(seconds: 10);
  static bool _didApplyNearbyBootDefault = false;

  String _topUid = "";
  String _topDistanceLabel = "Nearby";
  List<String> _topKeywords = const <String>[];
  final Map<String, Future<List<String>>> _sharedKeywordsCache =
      <String, Future<List<String>>>{};
    final Map<String, Stream<UserProfile?>> _profileWatchStreams =
      <String, Stream<UserProfile?>>{};

  // Ticks UI so decline cooldown chips count down live.
  // Kept intentionally low-frequency to reduce rebuild cost.
  Timer? _uiTick;
  Timer? _holdTick;
  Timer? _startupWindowTick;
  double _holdProgress01 = 0.0;
  bool _holdTriggeredActivation = false;
  DateTime? _suppressCircleTapUntil;
  bool _cycleUnlocked = false;
  bool _startupOffPromptActive = true;
  late final DateTime _startupOffTapUntil;
  late final AnimationController _orbitController;
  Duration? _orbitDuration;
  Stream<List<NearbyDoc>>? _nearbyStream;
  double? _nearbyStreamRadiusMiles;
  String? _nearbyStreamUid;
  bool? _nearbyStreamLocationEnabled;
  int _nearbyRequest = 0;
  bool _retryingNearby = false;
  bool _nearbyStreamCompleted = false;
  bool _nearbyResultsReady = false;
  String? _userInitiatedRetryUid;
  List<NearbyDoc>? _filterInput;
  MatchDiscoverySettings? _filterDiscovery;
  Future<List<NearbyDoc>>? _filterFuture;
  List<NearbyDoc>? _rankInput;
  MatchDiscoverySettings? _rankDiscovery;
  String? _rankParty;
  Set<String>? _rankMembers;
  Future<List<MatchCandidate>>? _rankFuture;
  StreamSubscription<DateTime?>? _incomingDeadlineSub;
  DateTime? _incomingDeadline;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GeoQueryService.instance.debug.addListener(_onNearbyStatusChanged);
    LocationPrivacyService.instance.addListener(_onNearbyStatusChanged);
    _startupOffTapUntil = DateTime.now().add(_kStartupTapOffWindow);

    if (!_didApplyNearbyBootDefault) {
      _didApplyNearbyBootDefault = true;
      MatchingModeService.instance.setModeKind(MatchingModeKind.normal);
      MatchingModeService.instance.setMode(ProxMatchingMode.passive);
    }

    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();

    _startupWindowTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (!_startupOffWindowOpen || !_startupOffPromptActive) {
        _startupWindowTick?.cancel();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    });

    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.trim().isNotEmpty) {
      _incomingDeadlineSub = ChatGateService.instance
          .watchIncomingRequestDeadline(forUid: uid)
          .listen((deadline) {
            if (!mounted) return;
            setState(() {
              _incomingDeadline = deadline;
            });
          });
    }

    unawaited(PresenceWriter.instance.startLive(reason: "nearby_open"));
    unawaited(PresenceWriter.instance.forceWrite(reason: "nearby_open"));
    _uiTick = Timer.periodic(const Duration(seconds: 2), (_) {
      ActiveModePolicyService.instance.evaluateAndApplyPenaltyIfNeeded();
      unawaited(
        ChatGateService.instance.enforceExpiredIncomingRequestsIfNeeded(
          forUid: uid,
        ),
      );
      if (!mounted) return;
      setState(() {});
    });
  }

  String _modeChipLabel(MatchDiscoverySettings d) {
    switch (d.modeKind) {
      case MatchingModeKind.off:
        return "Matching Off";
      case MatchingModeKind.listen:
        return "Listen Mode (${_listenRoleLabel(d.listenRole)})";
      case MatchingModeKind.treasureHunt:
        return "Treasure Hunt";
      case MatchingModeKind.travel:
        return "Travel";
      case MatchingModeKind.normal:
        if (d.normalMode == NormalMatchMode.active) {
          if (d.isActiveLocked) return "Active locked";
          return "Normal Active";
        }
        return "Normal Passive";
    }
  }

  String _keywordModeLabel(KeywordMatchMode mode) {
    switch (mode) {
      case KeywordMatchMode.strict:
        return "Strict";
      case KeywordMatchMode.singleKeyword:
        return "Single keyword";
      case KeywordMatchMode.reciprocalOpposite:
        return "Reciprocal";
      case KeywordMatchMode.keywordChain:
        return "Keyword chain";
      case KeywordMatchMode.similar:
        return "Similar";
    }
  }

  String _listenRoleLabel(ListenMatchRole role) {
    return role == ListenMatchRole.speak ? "Speak" : "Listen";
  }

  Color _proxCircleAccentColor(MatchDiscoverySettings discovery) {
    switch (discovery.modeKind) {
      case MatchingModeKind.listen:
        return discovery.listenRole == ListenMatchRole.speak
            ? const Color(0xFF2AB8A6)
            : const Color(0xFF35A4FF);
      case MatchingModeKind.treasureHunt:
        return const Color(0xFFF0C04E);
      case MatchingModeKind.travel:
        return const Color(0xFF4CB8F7);
      case MatchingModeKind.normal:
        return discovery.normalMode == NormalMatchMode.active
            ? const Color(0xFF22DE74)
            : const Color(0xFFE7B29F);
      case MatchingModeKind.off:
        return const Color(0xFF8A8F98);
    }
  }

  Future<void> _toggleBusinessOnly(MatchDiscoverySettings discovery) async {
    final next = discovery.copyWith(businessOnly: !discovery.businessOnly);
    UserSettingsService.instance.updateMatchDiscovery(next);
    UserSettingsService.instance.setRadiusMiles(next.radiusMiles);
    if (mounted) setState(() {});
  }

  Widget _panelPill({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    final accent = color ?? cs.primary.withValues(alpha: 0.86);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withValues(alpha: 0.58)),
          color: cs.surface.withValues(alpha: 0.10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNearbyStatusPanel(
    MatchDiscoverySettings discovery,
    ColorScheme cs,
    double radiusMiles,
  ) {
    final bool showActiveTag =
        discovery.modeKind == MatchingModeKind.normal &&
        discovery.normalMode == NormalMatchMode.active;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: ProxGlass(
          radius: 22,
          blurSigma: 18,
          fillOpacity: 0.10,
          borderOpacity: 0.16,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surface.withValues(alpha: 0.10),
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.22),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(Icons.my_location, color: cs.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Mode: ${_modeChipLabel(discovery)}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontSize: 39 / 2,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface.withValues(alpha: 0.90),
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Radius: ${radiusMiles.toStringAsFixed(1)} mi",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 36 / 2,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withValues(alpha: 0.78),
                      ),
                    ),
                    Text(
                      "Filter: ${discovery.businessOnly ? "Business only" : "All profiles"}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 36 / 2,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withValues(alpha: 0.78),
                      ),
                    ),
                    Text(
                      "Keywords: ${_keywordModeLabel(discovery.keywordMode)}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 36 / 2,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withValues(alpha: 0.78),
                      ),
                    ),
                    if (discovery.modeKind == MatchingModeKind.listen)
                      Text(
                        "Role: ${_listenRoleLabel(discovery.listenRole)}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 36 / 2,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface.withValues(alpha: 0.78),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _panelPill(
                    icon: Icons.tune,
                    label: "Mode",
                    onTap: _openModeChooser,
                    color: const Color(0xFFEFB6A3),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _panelPill(
                        icon: Icons.my_location,
                        label: "Radius",
                        onTap: _openModeChooser,
                        color: const Color(0xFFEFB6A3),
                      ),
                      if (showActiveTag) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: cs.surface.withValues(alpha: 0.18),
                          ),
                          child: Text(
                            "Active",
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurface.withValues(alpha: 0.72),
                                ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  _panelPill(
                    icon: Icons.storefront_outlined,
                    label: discovery.businessOnly ? "Biz ON" : "Biz OFF",
                    onTap: () => _toggleBusinessOnly(discovery),
                    color: const Color(0xFFEFB6A3),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GeoQueryService.instance.debug.removeListener(_onNearbyStatusChanged);
    LocationPrivacyService.instance.removeListener(_onNearbyStatusChanged);
    _uiTick?.cancel();
    _holdTick?.cancel();
    _startupWindowTick?.cancel();
    _orbitController.dispose();
    _incomingDeadlineSub?.cancel();
    super.dispose();
  }

  bool get _startupOffWindowOpen =>
      DateTime.now().isBefore(_startupOffTapUntil);

  Duration get _startupOffWindowLeft {
    final d = _startupOffTapUntil.difference(DateTime.now());
    return d > Duration.zero ? d : Duration.zero;
  }

  bool _isNewUser(UserProfile? profile) {
    if (profile == null) return false;
    final DateTime? joinedAt = profile.joinedAt;
    if (joinedAt == null) return false;
    return DateTime.now().difference(joinedAt).inDays <= _newUserWindowDays;
  }

  Future<List<String>> _sharedKeywordsForCandidate(String uid) {
    final String id = uid.trim();
    if (id.isEmpty) return Future.value(const <String>[]);
    return _sharedKeywordsCache.putIfAbsent(
      id,
      () => MatchingRuntimeService.instance.sharedKeywordsWith(id),
    );
  }

  Stream<UserProfile?> _profileStreamForCandidate(String uid) {
    final String id = uid.trim();
    if (id.isEmpty) return const Stream<UserProfile?>.empty();
    return _profileWatchStreams.putIfAbsent(
      id,
      () => UserProfileService.instance.watchProfile(id),
    );
  }

  bool get _showStartupOffCountdown {
    return _startupOffPromptActive && !_cycleUnlocked && _startupOffWindowOpen;
  }

  void _snack(String msg) {
    // Intentionally no-op on Nearby to avoid transient overlays that can disrupt animation.
  }

  String _fmtMMSS(Duration d) {
    final s = d.inSeconds < 0 ? 0 : d.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, "0");
    final ss = (s % 60).toString().padLeft(2, "0");
    return "$mm:$ss";
  }

  void _syncOrbitAnimation(MatchDiscoverySettings discovery) {
    if (discovery.modeKind == MatchingModeKind.off) {
      _orbitController.stop();
      _orbitController.value = 0.0;
      _orbitDuration = null;
      return;
    }

    final Duration nextDuration;
    switch (discovery.modeKind) {
      case MatchingModeKind.listen:
        nextDuration = discovery.listenRole == ListenMatchRole.speak
            ? const Duration(milliseconds: 1400)
            : const Duration(milliseconds: 2200);
        break;
      case MatchingModeKind.treasureHunt:
        nextDuration = const Duration(milliseconds: 1700);
        break;
      case MatchingModeKind.travel:
        nextDuration = const Duration(milliseconds: 2300);
        break;
      case MatchingModeKind.normal:
        nextDuration = discovery.normalMode == NormalMatchMode.active
            ? const Duration(milliseconds: 1200)
            : const Duration(milliseconds: 2600);
        break;
      case MatchingModeKind.off:
        nextDuration = const Duration(milliseconds: 3200);
        break;
    }

    if (_orbitDuration == nextDuration) {
      if (!_orbitController.isAnimating) {
        _orbitController.repeat();
      }
      return;
    }
    _orbitDuration = nextDuration;
    _orbitController.duration = nextDuration;
    _orbitController.repeat();
  }

  void _setListenRole(ListenMatchRole role) {
    final current = MatchingModeService.instance.discovery.listenRole;
    if (current == role) return;
    MatchingModeService.instance.setListenRole(role);
    _snack("Listen role set to ${_listenRoleLabel(role)}.");
    if (mounted) setState(() {});
  }

  Future<void> _setNormalMode(NormalMatchMode mode) async {
    final current = MatchingModeService.instance.discovery.normalMode;
    if (current == mode) return;
    if (mode == NormalMatchMode.active && !await _confirmActiveMode()) return;
    MatchingModeService.instance.setMode(
      mode == NormalMatchMode.active
          ? ProxMatchingMode.active
          : ProxMatchingMode.passive,
    );
    if (mode == NormalMatchMode.active) {
      _cycleUnlocked = true;
    }
    _snack(
      "Normal mode: ${mode == NormalMatchMode.active ? "Active" : "Passive"}.",
    );
    if (mounted) setState(() {});
  }

  Future<bool> _confirmActiveMode() async {
    if (_showingActiveConfirmation || !mounted) return false;
    _showingActiveConfirmation = true;
    final accepted =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.bolt, color: Color(0xFF22DE74)),
            title: const Text("Ready right now?"),
            content: const Text(
              "Active Mode is only for immediate availability to match, chat, "
              "and meet up. If you do not respond to an incoming request, "
              "Active Mode will be locked for 10 minutes.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text("Not now"),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.bolt),
                label: const Text("I'm available"),
              ),
            ],
          ),
        ) ??
        false;
    _showingActiveConfirmation = false;
    return accepted;
  }

  void _cycleModeKindFromCircle(MatchDiscoverySettings discovery) {
    if (!_cycleUnlocked) return;

    final next = ProxCircleInteractionPolicy.nextMode(discovery.modeKind);

    MatchingModeService.instance.setModeKind(next);
    _snack("Mode: ${_modeChipLabel(MatchingModeService.instance.discovery)}");
    if (mounted) setState(() {});
  }

  void _onCircleTap(MatchDiscoverySettings discovery) {
    final suppressUntil = _suppressCircleTapUntil;
    if (ProxCircleInteractionPolicy.shouldSuppressTap(
      now: DateTime.now(),
      suppressUntil: suppressUntil,
    )) {
      return;
    }
    _suppressCircleTapUntil = null;

    // Off must never be a dead end. Restoring Normal Passive is available
    // regardless of the startup countdown or the local cycle state.
    if (discovery.modeKind == MatchingModeKind.off) {
      MatchingModeService.instance.setMode(ProxMatchingMode.passive);
      _startupOffPromptActive = false;
      _snack("Normal Passive restored.");
      if (mounted) setState(() {});
      return;
    }

    final userSettings = UserSettingsService.instance.current;
    if (userSettings.simpleModeEnabled && !userSettings.alwaysUseNormalMode) {
      final next = discovery.normalMode == NormalMatchMode.active
          ? NormalMatchMode.passive
          : NormalMatchMode.active;
      unawaited(_setNormalMode(next));
      return;
    }

    final bool isNormalPassive =
        discovery.modeKind == MatchingModeKind.normal &&
        discovery.normalMode == NormalMatchMode.passive;

    // Active and advanced modes prove that cycling was already unlocked,
    // including after Nearby is rebuilt or the app resumes.
    if (ProxCircleInteractionPolicy.canCycle(
      discovery: discovery,
      sessionUnlocked: _cycleUnlocked,
    )) {
      _cycleUnlocked = true;
    }

    if (!_cycleUnlocked && isNormalPassive && !_showStartupOffCountdown) {
      // After the startup off window expires, a normal tap should cycle modes.
      _cycleUnlocked = true;
    }

    if (!_cycleUnlocked) {
      if (isNormalPassive && _showStartupOffCountdown) {
        _startupOffPromptActive = false;
        MatchingModeService.instance.setModeKind(MatchingModeKind.off);
        _snack("Matching Off enabled.");
        if (mounted) setState(() {});
      } else if (isNormalPassive) {
        _snack("Hold 3s to turn on Active Matching.");
      }
      return;
    }

    _cycleModeKindFromCircle(discovery);
  }

  void _enforceSimpleDiscoveryDefaults(MatchDiscoverySettings discovery) {
    final fixed = SimpleModePolicy.lockedDiscoveryDefaults(discovery);
    if (discovery == fixed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UserSettingsService.instance.updateMatchDiscovery(fixed);
    });
  }

  Widget _buildSimpleSearchSettings(
    MatchDiscoverySettings discovery,
    ColorScheme cs,
  ) {
    return SliverToBoxAdapter(
      child: Card(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_outline, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    "Match search settings",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "Simple Mode keeps search at safe defaults. Only Active and Passive are available.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SegmentedButton<NormalMatchMode>(
                segments: const [
                  ButtonSegment(
                    value: NormalMatchMode.active,
                    icon: Icon(Icons.radar),
                    label: Text("Active"),
                  ),
                  ButtonSegment(
                    value: NormalMatchMode.passive,
                    icon: Icon(Icons.visibility_outlined),
                    label: Text("Passive"),
                  ),
                ],
                selected: <NormalMatchMode>{discovery.normalMode},
                onSelectionChanged: (value) {
                  unawaited(_setNormalMode(value.first));
                },
              ),
              const Divider(height: 24),
              const _LockedSearchRow(label: "Mode", value: "Normal"),
              const _LockedSearchRow(label: "Radius", value: "2 miles"),
              const _LockedSearchRow(label: "Keywords", value: "Similar"),
              const _LockedSearchRow(label: "Age", value: "Any age"),
              const _LockedSearchRow(label: "Visibility", value: "Public"),
            ],
          ),
        ),
      ),
    );
  }

  void _turnMatchingOffFromActive() {
    MatchingModeService.instance.setModeKind(MatchingModeKind.off);
    _startupOffPromptActive = false;
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _onHoldProxCircle(MatchDiscoverySettings discovery) async {
    if (discovery.modeKind != MatchingModeKind.normal) {
      _snack("Set mode to Normal first.");
      return;
    }
    if (discovery.normalMode == NormalMatchMode.active) return;

    if (discovery.isActiveLocked) {
      final left = Duration(
        milliseconds:
            (discovery.activeLockUntilEpochMs -
                    DateTime.now().millisecondsSinceEpoch)
                .clamp(0, 1 << 30),
      );
      _snack("Active is locked for ${_fmtMMSS(left)}.");
      return;
    }

    _holdTick?.cancel();
    _holdTick = null;
    _holdProgress01 = 0.0;
    _holdTriggeredActivation = false;
    _startupOffPromptActive = false;

    if (!await _confirmActiveMode()) {
      if (mounted) setState(() {});
      return;
    }

    _holdTriggeredActivation = true;
    MatchingModeService.instance.setMode(ProxMatchingMode.active);
    _cycleUnlocked = true;
    _suppressCircleTapUntil = DateTime.now().add(
      const Duration(milliseconds: 450),
    );
    _snack("Active mode enabled.");
    if (mounted) setState(() {});
  }

  void _beginHoldToActivate(MatchDiscoverySettings discovery) {
    if (discovery.modeKind != MatchingModeKind.normal) return;
    if (discovery.normalMode == NormalMatchMode.active) return;
    if (discovery.isActiveLocked) return;
    if (_startupOffWindowOpen && !_cycleUnlocked) return;

    _holdTick?.cancel();
    _holdTriggeredActivation = false;
    final DateTime startedAt = DateTime.now();

    _holdTick = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted) return;
      final int elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      final double p = (elapsedMs / _kHoldToActivateDuration.inMilliseconds)
          .clamp(0.0, 1.0);
      setState(() {
        _holdProgress01 = p;
      });
      if (p >= 1.0) {
        unawaited(_onHoldProxCircle(discovery));
      }
    });
  }

  Duration? _activePresenceTimeLeft(Map<String, dynamic> profile) {
    final presence = profile["presence"];
    if (presence is! Map) return null;
    final expiresAt = presence["expiresAt"];
    if (expiresAt is! Timestamp) return null;
    final left = expiresAt.toDate().difference(DateTime.now());
    return left > Duration.zero ? left : Duration.zero;
  }

  void _endHoldToActivate() {
    _holdTick?.cancel();
    _holdTick = null;

    if (_holdTriggeredActivation) {
      _holdTriggeredActivation = false;
      return;
    }

    if (!mounted) return;
    setState(() {
      _holdProgress01 = 0.0;
    });
  }

  String _modeCircleLabel(MatchDiscoverySettings discovery) {
    switch (discovery.modeKind) {
      case MatchingModeKind.off:
        return "OFF";
      case MatchingModeKind.normal:
        return "NORMAL";
      case MatchingModeKind.listen:
        return "LISTEN";
      case MatchingModeKind.treasureHunt:
        return "TREASURE";
      case MatchingModeKind.travel:
        return "TRAVEL";
    }
  }

  Future<void> _openChat({required String otherUid}) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (myUid.isEmpty) {
      _snack("Sign in to open chat.");
      return;
    }

    if (_opening) return;
    setState(() {
      _opening = true;
      _openingUid = otherUid;
    });

    try {
      // IMPORTANT: pre-check decline cooldown BEFORE creating/ensuring chat doc.
      // ChatThreadService.chatIdFor is deterministic, so we can safely compute it.
      final String predictedChatId = ChatThreadService.instance.chatIdFor(
        myUid,
        otherUid,
      );

      final Duration? left = await MeetupService.instance.declineCooldownLeft(
        predictedChatId,
      );
      if (left != null && left > Duration.zero) {
        if (!mounted) return;
        _snack("Meetup declined - try again in ${_fmtMMSS(left)}.");
        return;
      }

      final chatId = await ChatThreadService.instance
          .ensureChat(myUid: myUid, otherUid: otherUid)
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamed("/chat", arguments: {"chatId": chatId, "otherUid": otherUid});
    } catch (_) {
      _snack("Couldn't open chat right now.");
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
          _openingUid = "";
        });
      }
    }
  }

  Future<void> _openModeChooser() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const MatchingModeScreen(),
        fullscreenDialog: true,
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openTreasureHunt() async {
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const TreasureHuntScreen()));
  }

  Future<void> _showMatchFoundForTop() async {
    if (!_nearbyResultsReady ||
        GeoQueryService.instance.debug.status != GeoQueryStatus.ready) {
      _snack('Nearby is not ready yet. Check the status below.');
      return;
    }
    final request = _nearbyRequest;
    final uid = _topUid.trim();
    if (uid.isEmpty) {
      _snack("No matches nearby yet.");
      return;
    }
    if (!mounted) return;

    final List<String> resolved = _topKeywords.isNotEmpty
        ? _topKeywords
        : await _sharedKeywordsForCandidate(uid)
              .timeout(
                const Duration(seconds: 2),
                onTimeout: () => const <String>[],
              )
              .then((value) => value.take(3).toList(growable: false));
    final List<String> keywords = resolved.isNotEmpty
        ? resolved
        : const <String>["Shared interest", "Nearby", "Right now"];

    if (!mounted ||
        !_nearbyResultsReady ||
        request != _nearbyRequest ||
        uid != _topUid)
      return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => MatchFoundSheet(
        distanceLabel: _topDistanceLabel.trim().isEmpty
            ? "Nearby"
            : _topDistanceLabel,
        keywords: keywords,
        highlightMatchedKeywords: true,
        showMatchedLabel: true,
        onIgnore: () => Navigator.of(context).pop(),
        onSayHi: () {
          Navigator.of(context).pop();
          _openChat(otherUid: uid);
        },
      ),
    );
  }

  Widget _chip(String text, {bool strong = false, Color? accent}) {
    final cs = Theme.of(context).colorScheme;
    final Color chipAccent = accent ?? cs.outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipAccent == cs.outline
            ? cs.surface.withValues(alpha: 0.10)
            : chipAccent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: chipAccent.withValues(alpha: 0.30)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: accent == null
              ? (strong ? cs.onSurface : cs.onSurface.withValues(alpha: 0.72))
              : cs.onSurface,
          fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }

  Widget _matchChip(String text) {
    final Color accent = const Color(0xFF21C77F);
    return _chip(text, strong: true, accent: accent);
  }

  Widget _gateChipFrom(
    ChatGateStatus? gate,
    String myUid, {
    required bool cooling,
  }) {
    if (cooling) return _chip("Meetup paused", strong: true);
    if (gate == null) return _chip("Chat requested", strong: true);

    final status = gate.status.trim();
    if (status.isEmpty) return _chip("Chat requested", strong: true);

    if (status == "accepted") return _chip("Chat open", strong: true);
    if (status == "declined") return _chip("Chat declined");
    if (status == "expired") return _chip("Chat request expired");

    final byMe = gate.requestedBy.isNotEmpty && gate.requestedBy == myUid;
    return byMe ? _chip("Request sent") : _chip("Chat requested", strong: true);
  }

  Widget _inlineGateActions({
    required String chatId,
    required String otherUid,
    required String myUid,
    required ChatGateStatus? gate,
    required bool cooling,
    required bool openingThis,
  }) {
    final cs = Theme.of(context).colorScheme;

    if (myUid.isEmpty) return const SizedBox.shrink();
    if (openingThis) return const SizedBox.shrink();
    if (cooling) return const SizedBox.shrink();
    if (gate == null) return const SizedBox.shrink();

    // Only show when it's pending AND requested by the other person.
    if (gate.isAccepted || gate.isDeclined || gate.isExpired) {
      return const SizedBox.shrink();
    }
    final String requestedBy = gate.requestedBy.trim();
    if (requestedBy.isEmpty) return const SizedBox.shrink();
    if (requestedBy == myUid) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: "Accept chat",
          onPressed: () async {
            try {
              await ChatGateService.instance.accept(
                chatId: chatId,
                accepterUid: myUid,
              );
              if (!mounted) return;
              _snack("Chat accepted");
              // Accept should flow directly into chat.
              await _openChat(otherUid: otherUid);
            } catch (_) {
              if (!mounted) return;
              _snack("Couldn't accept chat");
            }
          },
          icon: Icon(Icons.check_circle, color: cs.primary),
        ),
        IconButton(
          tooltip: "Decline chat",
          onPressed: () async {
            try {
              await ChatGateService.instance.decline(
                chatId: chatId,
                declinerUid: myUid,
              );
              if (!mounted) return;
              _snack("Chat declined");
            } catch (_) {
              if (!mounted) return;
              _snack("Couldn't decline chat");
            }
          },
          icon: Icon(Icons.cancel, color: cs.onSurface.withValues(alpha: 0.72)),
        ),
      ],
    );
  }

  List<NearbyDoc> _applyBusinessFilter(
    List<NearbyDoc> nearby,
    MatchDiscoverySettings discovery,
  ) {
    if (!discovery.businessOnly) return nearby;

    final bool immediateOnly = discovery.immediateOnly;

    return nearby
        .where((d) {
          if (!d.isBusiness) return false;
          if (!immediateOnly) return true;
          final mins = d.availabilityMinutes;
          return mins != null && mins <= 0;
        })
        .toList(growable: false);
  }

  List<NearbyDoc> _applyAgeFilter(
    List<NearbyDoc> nearby,
    MatchDiscoverySettings discovery,
  ) {
    if (discovery.ageBracket == MatchAgeBracket.any) return nearby;

    final int? minAge = discovery.ageBracket.minAge;
    final int? maxAge = discovery.ageBracket.maxAge;

    return nearby
        .where((d) {
          final int? age = _extractCandidateAgeYears(d.data);
          if (age == null) return false;
          if (minAge != null && age < minAge) return false;
          if (maxAge != null && age > maxAge) return false;
          return true;
        })
        .toList(growable: false);
  }

  int? _extractCandidateAgeYears(Map<String, dynamic> data) {
    final int? explicitAge = _parseAgeYears(data["ageYears"] ?? data["age"]);
    if (explicitAge != null) return explicitAge;

    final int? birthYear = _parseBirthYear(
      data["birthYear"] ?? data["birth_year"],
    );
    if (birthYear != null) {
      final int years = DateTime.now().year - birthYear;
      if (years >= 13 && years <= 120) return years;
    }

    final DateTime? dob = _parseDateOfBirth(
      data["dateOfBirth"] ??
          data["dob"] ??
          data["birthDate"] ??
          data["birthday"],
    );
    if (dob == null) return null;

    final now = DateTime.now();
    int age = now.year - dob.year;
    final bool hadBirthdayThisYear =
        now.month > dob.month || (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthdayThisYear) {
      age -= 1;
    }
    if (age < 13 || age > 120) return null;
    return age;
  }

  int? _parseAgeYears(dynamic raw) {
    if (raw is num) {
      final int value = raw.toInt();
      if (value >= 13 && value <= 120) return value;
      return null;
    }
    if (raw is String) {
      final int? value = int.tryParse(raw.trim());
      if (value != null && value >= 13 && value <= 120) {
        return value;
      }
    }
    return null;
  }

  int? _parseBirthYear(dynamic raw) {
    if (raw is num) {
      final int year = raw.toInt();
      if (year >= 1900 && year <= DateTime.now().year) return year;
      return null;
    }
    if (raw is String) {
      final int? year = int.tryParse(raw.trim());
      if (year != null && year >= 1900 && year <= DateTime.now().year) {
        return year;
      }
    }
    return null;
  }

  DateTime? _parseDateOfBirth(dynamic raw) {
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    if (raw is String) {
      return DateTime.tryParse(raw.trim());
    }
    return null;
  }

  Future<void> _captureTopCandidate(List<dynamic> items) async {
    final request = _nearbyRequest;
    final ranking = _rankFuture;
    final viewerUid = FirebaseAuth.instance.currentUser?.uid;
    if (GeoQueryService.instance.debug.status != GeoQueryStatus.ready) return;
    if (items.isEmpty) return;

    final dynamic c0 = items.first;
    final String uid = (c0.uid ?? "").toString();
    if (uid.isEmpty) return;

    final double? miles = (c0.distanceMiles is num)
        ? (c0.distanceMiles as num).toDouble()
        : null;
    final String label = (miles == null)
        ? "Nearby"
        : (ProxDistanceFormat.bucketMilesOrNull(miles) ?? "Nearby");

    final List<String> top3 = (await _sharedKeywordsForCandidate(uid).timeout(
      const Duration(seconds: 2),
      onTimeout: () => const <String>[],
    )).take(3).toList(growable: false);

    final bool changed =
        uid != _topUid ||
        label != _topDistanceLabel ||
        !_listEq(top3, _topKeywords);

    if (changed) {
      if (!mounted ||
          !_nearbyResultsReady ||
          request != _nearbyRequest ||
          !identical(ranking, _rankFuture) ||
          viewerUid != FirebaseAuth.instance.currentUser?.uid ||
          GeoQueryService.instance.debug.status != GeoQueryStatus.ready)
        return;
      setState(() {
        _topUid = uid;
        _topDistanceLabel = label;
        _topKeywords = top3;
      });
    }
  }

  static bool _listEq(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _onNearbyStatusChanged() {
    if (!mounted) return;
    setState(() {
      final status = GeoQueryService.instance.debug.status;
      if (status != GeoQueryStatus.loading && status != GeoQueryStatus.idle) {
        _retryingNearby = false;
      }
      if (status != GeoQueryStatus.ready ||
          !LocationPrivacyService.instance.locationEnabled) {
        _nearbyResultsReady = false;
        _topUid = '';
        _topKeywords = const [];
        _topDistanceLabel = 'Nearby';
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    if (_nearbyStreamCompleted ||
        GeoQueryService.instance.debug.status != GeoQueryStatus.ready) {
      setState(_invalidateNearbyStream);
    }
  }

  void _invalidateNearbyStream({bool userInitiated = false}) {
    _userInitiatedRetryUid = userInitiated
        ? FirebaseAuth.instance.currentUser?.uid
        : null;
    GeoQueryService.instance.clearSession();
    _nearbyResultsReady = false;
    _nearbyStream = null;
    _filterFuture = null;
    _rankFuture = null;
    _profileWatchStreams.clear();
    _topUid = '';
    _topKeywords = const [];
    _topDistanceLabel = 'Nearby';
  }

  void _retryNearby() {
    if (_retryingNearby || !LocationPrivacyService.instance.locationEnabled)
      return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() {
      _retryingNearby = true;
      _invalidateNearbyStream(userInitiated: true);
    });
    // Restart the query immediately. Presence refresh must not add a second GPS
    // timeout before a failed search can recover.
    unawaited(
      PresenceWriter.instance.forceWrite(reason: 'nearby_retry').catchError((
        Object error,
        StackTrace stack,
      ) {
        if (FirebaseAuth.instance.currentUser?.uid == uid) {
          RuntimeDiagnosticsService.instance.record(
            error,
            stack,
            operation: 'Refresh nearby presence',
          );
        }
      }),
    );
  }

  void _openNearbyLocationSettings() {
    Navigator.of(context).pushNamed('/settings');
  }

  Future<List<NearbyDoc>> _filteredNearby(
    List<NearbyDoc> raw,
    MatchDiscoverySettings discovery,
  ) {
    if (_filterFuture != null &&
        identical(raw, _filterInput) &&
        discovery == _filterDiscovery)
      return _filterFuture!;
    _filterInput = raw;
    _filterDiscovery = discovery;
    final nearby = _applyAgeFilter(
      _applyBusinessFilter(raw, discovery),
      discovery,
    );
    return _filterFuture = MatchingRuntimeService.instance
        .filterByModeForSettings(nearby, discovery)
        .timeout(const Duration(seconds: 20));
  }

  Future<List<MatchCandidate>> _rankedNearby(
    List<NearbyDoc> nearby,
    MatchDiscoverySettings discovery,
    String? partyId,
    Set<String> members,
  ) {
    if (_rankFuture != null &&
        identical(nearby, _rankInput) &&
        discovery == _rankDiscovery &&
        partyId == _rankParty &&
        setEquals(members, _rankMembers))
      return _rankFuture!;
    _rankInput = nearby;
    _rankDiscovery = discovery;
    _rankParty = partyId;
    _rankMembers = Set.of(members);
    return _rankFuture = MatchPipeline.instance
        .buildCandidates(
          nearby: nearby,
          myPartyId: partyId ?? '',
          discovery: discovery,
          partyMemberUids: members,
        )
        .timeout(const Duration(seconds: 20));
  }

  Widget _nearbyResultsGate(
    MatchDiscoverySettings discovery, {
    required bool loading,
    required bool failed,
  }) {
    _nearbyResultsReady = false;
    return NearbyResultsGate(
      status: GeoQueryService.instance.debug.status,
      locationEnabled: LocationPrivacyService.instance.locationEnabled,
      matchingEnabled: discovery.modeKind != MatchingModeKind.off,
      queryLoading: loading,
      queryFailed: failed,
      retrying: _retryingNearby,
      onRetry: _retryNearby,
      onSettings: _openNearbyLocationSettings,
      child: const SizedBox.shrink(),
    );
  }

  void _ensureNearbyStream(double radiusMiles) {
    final current = _nearbyStreamRadiusMiles;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final locationEnabled = LocationPrivacyService.instance.locationEnabled;
    if (_nearbyStream != null &&
        _nearbyStreamUid == uid &&
        _nearbyStreamLocationEnabled == locationEnabled &&
        current != null &&
        (current - radiusMiles).abs() < 0.001) {
      return;
    }
    _nearbyStreamRadiusMiles = radiusMiles;
    final userInitiated =
        uid != null &&
        _userInitiatedRetryUid == uid &&
        _nearbyStreamLocationEnabled == locationEnabled;
    _userInitiatedRetryUid = null;
    _nearbyStreamUid = uid;
    _nearbyStreamLocationEnabled = locationEnabled;
    _nearbyStreamCompleted = false;
    _nearbyRequest++;
    _filterFuture = null;
    _rankFuture = null;
    _nearbyStream = () async* {
      // Invalidate cancelled location/profile lookups before the replacement
      // query begins; async subscription keeps notifier work out of build().
      GeoQueryService.instance.clearSession();
      if (!locationEnabled || uid == null) {
        yield const <NearbyDoc>[];
        return;
      }
      yield* GeoQueryService.instance.streamNearby(
        center: null,
        radiusMiles: radiusMiles,
        userInitiated: userInitiated,
      );
    }();
  }

  Widget _buildProxCircleActivatorCard(
    MatchDiscoverySettings discovery,
    ColorScheme cs,
  ) {
    _syncOrbitAnimation(discovery);

    final accent = _proxCircleAccentColor(discovery);
    final bool isNormalMode = discovery.modeKind == MatchingModeKind.normal;
    final bool isOffMode = discovery.modeKind == MatchingModeKind.off;
    final bool isListenMode = discovery.modeKind == MatchingModeKind.listen;
    final userSettings = UserSettingsService.instance.current;
    final bool simpleModeActive =
      userSettings.simpleModeEnabled && !userSettings.alwaysUseNormalMode;
    final bool showActiveDot =
        discovery.modeKind == MatchingModeKind.normal &&
        discovery.normalMode == NormalMatchMode.active;
    final bool canHoldToActivate =
        isNormalMode &&
        discovery.normalMode == NormalMatchMode.passive &&
        !_showStartupOffCountdown;
    final bool showHoldProgress = canHoldToActivate && _holdProgress01 > 0;
    final bool animateOrbit = !isOffMode;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: Column(
          key: _kNearbyProxCircleAnchorKey,
          children: [
            GestureDetector(
              onTapDown: canHoldToActivate
                  ? (_) => _beginHoldToActivate(discovery)
                  : null,
              onTapUp: canHoldToActivate ? (_) => _endHoldToActivate() : null,
              onTapCancel: canHoldToActivate ? _endHoldToActivate : null,
              onTap: () => _onCircleTap(discovery),
              child: SizedBox(
                width: 196,
                height: 196,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (showHoldProgress)
                      CustomPaint(
                        size: const Size.square(196),
                        painter: _ProxHoldRingPainter(
                          progress01: _holdProgress01,
                          color:
                              Color.lerp(
                                const Color(0xFF2ECF6B),
                                const Color(0xFF22DE74),
                                _holdProgress01,
                              ) ??
                              const Color(0xFF22DE74),
                        ),
                      ),
                    if (isNormalMode && showActiveDot)
                      AnimatedBuilder(
                        animation: _orbitController,
                        builder: (context, _) {
                          final pulse =
                              0.82 +
                              (0.18 *
                                  math.sin(
                                    _orbitController.value * math.pi * 2,
                                  ));
                          return Opacity(
                            opacity: pulse.clamp(0.3, 1.0),
                            child: Container(
                              width: 194,
                              height: 194,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: accent.withValues(alpha: 0.46),
                                  width: 2,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    Container(
                      width: 178,
                      height: 178,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: accent, width: 4),
                        gradient: RadialGradient(
                          colors: [
                            cs.surface.withValues(alpha: 0.82),
                            cs.surface.withValues(alpha: 0.42),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isOffMode
                                ? Colors.transparent
                                : accent.withValues(alpha: 0.34),
                            blurRadius: isOffMode ? 0 : 30,
                            spreadRadius: isOffMode ? 0 : 3,
                          ),
                        ],
                      ),
                      child: AnimatedBuilder(
                        animation: _orbitController,
                        builder: (context, _) {
                          final angle = animateOrbit
                              ? _orbitController.value * (2 * math.pi)
                              : 0.0;
                          return Stack(
                            children: [
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AnimatedBuilder(
                                      animation: _orbitController,
                                      builder: (context, __) {
                                        final pulse = isOffMode
                                            ? 0.0
                                            : (0.68 +
                                                  (0.32 *
                                                      math
                                                          .sin(
                                                            _orbitController
                                                                    .value *
                                                                math.pi *
                                                                2,
                                                          )
                                                          .abs()));
                                        return Container(
                                          width: 104,
                                          height: 104,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF35A4FF)
                                                    .withValues(
                                                      alpha: pulse * 0.75,
                                                    ),
                                                blurRadius: 28,
                                                spreadRadius: 2,
                                              ),
                                            ],
                                          ),
                                          child: const Center(
                                            child: ColorFiltered(
                                              colorFilter:
                                                  ColorFilter.matrix(<double>[
                                                    0,
                                                    0,
                                                    0,
                                                    0,
                                                    255,
                                                    0,
                                                    0,
                                                    0,
                                                    0,
                                                    255,
                                                    0,
                                                    0,
                                                    0,
                                                    0,
                                                    255,
                                                    0.596,
                                                    2.002,
                                                    0.202,
                                                    0,
                                                    -180,
                                                  ]),
                                              child: Image(
                                                image: AssetImage(
                                                  "img/prox-logo-new-lettering.png",
                                                ),
                                                width: 92,
                                                height: 92,
                                                fit: BoxFit.contain,
                                                filterQuality:
                                                    FilterQuality.high,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _modeCircleLabel(discovery),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.0,
                                            color: accent.withValues(
                                              alpha: 0.92,
                                            ),
                                          ),
                                    ),
                                    if (isNormalMode)
                                      Text(
                                        discovery.normalMode ==
                                                NormalMatchMode.active
                                            ? "ACTIVE"
                                            : "PASSIVE",
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.8,
                                              color: cs.onSurface.withValues(
                                                alpha: 0.78,
                                              ),
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                              Positioned.fill(
                                child: animateOrbit
                                    ? Transform.rotate(
                                        angle: angle,
                                        child: Align(
                                          alignment: Alignment.topCenter,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 14,
                                            ),
                                            child: Container(
                                              width: 10,
                                              height: 10,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: accent.withValues(
                                                  alpha: 0.92,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: accent.withValues(
                                                      alpha: 0.7,
                                                    ),
                                                    blurRadius: 12,
                                                    spreadRadius: 1,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              if (discovery.modeKind ==
                                      MatchingModeKind.treasureHunt &&
                                  animateOrbit)
                                Positioned.fill(
                                  child: Transform.rotate(
                                    angle: -angle,
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 13,
                                        ),
                                        child: Icon(
                                          Icons.explore,
                                          size: 16,
                                          color: accent.withValues(alpha: 0.9),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (discovery.modeKind ==
                                      MatchingModeKind.travel &&
                                  animateOrbit)
                                Positioned.fill(
                                  child: Transform.rotate(
                                    angle: angle * 1.35,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          left: 12,
                                        ),
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: accent.withValues(
                                              alpha: 0.86,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (isListenMode && animateOrbit)
                                Positioned(
                                  left: 58,
                                  right: 58,
                                  bottom: 42,
                                  child: AnimatedBuilder(
                                    animation: _orbitController,
                                    builder: (context, __) {
                                      final p =
                                          0.42 +
                                          (0.58 *
                                              math
                                                  .sin(
                                                    _orbitController.value *
                                                        math.pi *
                                                        2,
                                                  )
                                                  .abs());
                                      return Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: List<Widget>.generate(5, (i) {
                                          final h =
                                              4 + ((i.isEven ? p : 1 - p) * 10);
                                          return Container(
                                            width: 4,
                                            height: h,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              color: accent.withValues(
                                                alpha: 0.88,
                                              ),
                                            ),
                                          );
                                        }),
                                      );
                                    },
                                  ),
                                ),
                              if (showActiveDot)
                                Positioned(
                                  top: 18,
                                  right: 28,
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: accent,
                                      boxShadow: [
                                        BoxShadow(
                                          color: accent.withValues(alpha: 0.5),
                                          blurRadius: 10,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (isListenMode)
                                Positioned(
                                  top: 18,
                                  right: 28,
                                  child: Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: cs.surface.withValues(alpha: 0.90),
                                      border: Border.all(
                                        color: accent.withValues(alpha: 0.8),
                                      ),
                                    ),
                                    child: Icon(
                                      discovery.listenRole ==
                                              ListenMatchRole.speak
                                          ? Icons.mic_none
                                          : Icons.hearing,
                                      size: 14,
                                      color: accent,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              simpleModeActive
              ? (discovery.normalMode == NormalMatchMode.active
                ? "Tap circle to switch to Passive"
                : "Tap circle to switch to Active")
              : _cycleUnlocked
                  ? "Tap circle to cycle mode"
                  : isOffMode
                  ? "Matching is OFF"
                  : (isNormalMode &&
                        discovery.normalMode == NormalMatchMode.passive &&
                        _showStartupOffCountdown)
                  ? "Tap in ${_fmtMMSS(_startupOffWindowLeft)} to turn matching OFF"
                  : (isNormalMode &&
                        discovery.normalMode == NormalMatchMode.passive)
                  ? "Hold 3s to turn on Active Matching"
                  : "",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.84),
                fontWeight: FontWeight.w800,
              ),
            ),
            if (isNormalMode && _cycleUnlocked) ...[
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<NormalMatchMode>(
                  segments: const [
                    ButtonSegment(
                      value: NormalMatchMode.passive,
                      icon: Icon(Icons.spa_outlined),
                      label: Text("Passive"),
                    ),
                    ButtonSegment(
                      value: NormalMatchMode.active,
                      icon: Icon(Icons.flash_on_outlined),
                      label: Text("Active"),
                    ),
                  ],
                  selected: <NormalMatchMode>{discovery.normalMode},
                  onSelectionChanged: (next) {
                    if (next.isEmpty) return;
                    _setNormalMode(next.first);
                  },
                ),
              ),
            ],
            if (isListenMode) ...[
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<ListenMatchRole>(
                  segments: const [
                    ButtonSegment(
                      value: ListenMatchRole.speak,
                      icon: Icon(Icons.mic_none),
                      label: Text("Speak"),
                    ),
                    ButtonSegment(
                      value: ListenMatchRole.listen,
                      icon: Icon(Icons.hearing),
                      label: Text("Listen"),
                    ),
                  ],
                  selected: <ListenMatchRole>{discovery.listenRole},
                  onSelectionChanged: (next) {
                    if (next.isEmpty) return;
                    _setListenRole(next.first);
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Cross-role only: Speak users match Listen users.",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.74),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else if (showActiveDot) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _turnMatchingOffFromActive,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: cs.surface.withValues(alpha: 0.16),
                    border: Border.all(
                      color: cs.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    "Tap to turn matching off",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withValues(alpha: 0.86),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNearbyCardsScrollableArea({
    required MatchDiscoverySettings discovery,
    required String? myPartyId,
    required Set<String> partyMemberUids,
    required ColorScheme cs,
    required double bottomInset,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: 10, right: 10, bottom: 16 + bottomInset),
      child: StreamBuilder<List<NearbyDoc>>(
        key: ValueKey(_nearbyRequest),
        stream: _nearbyStream,
        builder: (context, snap) {
          _nearbyStreamCompleted = snap.connectionState == ConnectionState.done;
          final waiting =
              snap.connectionState == ConnectionState.none ||
              snap.connectionState == ConnectionState.waiting;
          if (_retryingNearby ||
              !LocationPrivacyService.instance.locationEnabled ||
              discovery.modeKind == MatchingModeKind.off ||
              GeoQueryService.instance.debug.status != GeoQueryStatus.ready ||
              waiting ||
              snap.hasError ||
              !snap.hasData) {
            return _nearbyResultsGate(
              discovery,
              loading: waiting,
              failed:
                  snap.hasError || (_nearbyStreamCompleted && !snap.hasData),
            );
          }
          final rawNearby = snap.data ?? const <NearbyDoc>[];

          return FutureBuilder<List<NearbyDoc>>(
            future: _filteredNearby(rawNearby, discovery),
            builder: (context, filteredSnap) {
              final filteredLoading =
                  filteredSnap.connectionState != ConnectionState.done;
              if (filteredSnap.hasError ||
                  (filteredLoading && !filteredSnap.hasData)) {
                return _nearbyResultsGate(
                  discovery,
                  loading: filteredLoading,
                  failed: filteredSnap.hasError,
                );
              }

              final modeFilteredNearby =
                  filteredSnap.data ?? const <NearbyDoc>[];

              return FutureBuilder<List<MatchCandidate>>(
                future: _rankedNearby(
                  modeFilteredNearby,
                  discovery,
                  myPartyId,
                  partyMemberUids,
                ),
                builder: (context, rankedSnap) {
                  final rankedLoading =
                      rankedSnap.connectionState != ConnectionState.done;
                  if (rankedSnap.hasError ||
                      (rankedLoading && !rankedSnap.hasData)) {
                    return _nearbyResultsGate(
                      discovery,
                      loading: rankedLoading,
                      failed: rankedSnap.hasError,
                    );
                  }

                  final items = rankedSnap.data ?? const <MatchCandidate>[];
                  _nearbyResultsReady = true;
                  if (items.isEmpty) {
                    if (_topUid.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          _topUid = "";
                          _topDistanceLabel = "Nearby";
                          _topKeywords = const <String>[];
                        });
                      });
                    }

                    return Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "No matches nearby",
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.72),
                                  ),
                            ),
                            const SizedBox(height: 12),
                            const ProxLogoMark(size: 36),
                            const SizedBox(height: 8),
                            const Text(
                              'Try again later or adjust your matching settings.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: _retryNearby,
                                  child: const Text('Retry'),
                                ),
                                TextButton(
                                  onPressed: _openModeChooser,
                                  child: const Text('Adjust matching'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    unawaited(_captureTopCandidate(items));
                  });

                  return ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final c = items[i];

                      final String myUid =
                          FirebaseAuth.instance.currentUser?.uid ?? "";
                      final String? chatId = myUid.isEmpty
                          ? null
                          : ChatThreadService.instance.chatIdFor(myUid, c.uid);

                      final bool openingThis = _opening && _openingUid == c.uid;

                      final Stream<DocumentSnapshot<Map<String, dynamic>>>
                      chatDocStream = (chatId == null)
                          ? const Stream<
                              DocumentSnapshot<Map<String, dynamic>>
                            >.empty()
                          : FirebaseFirestore.instance
                                .collection("chats")
                                .doc(chatId)
                                .snapshots();

                      // Do not speculatively watch protected meetup documents
                      // for every geo candidate. A meetup listener starts from
                      // the confirmed chat/meetup flow after both users match.
                      const Stream<MeetupRequestState?> meetupStream =
                          Stream<MeetupRequestState?>.empty();

                      NearbyDoc? nd;
                      for (final d in modeFilteredNearby) {
                        if (d.uid == c.uid) {
                          nd = d;
                          break;
                        }
                      }
                      final bool isBiz = nd?.isBusiness == true;
                      final int? avail = nd?.availabilityMinutes;
                      final bool isActivePeer = c.normalModePriority == 0;
                      final Duration? activeTimeLeft = isActivePeer
                          ? _activePresenceTimeLeft(c.profile)
                          : null;

                      final String? distLabel =
                          ProxDistanceFormat.bucketMilesOrNull(c.distanceMiles);
                      final bool isPartyScope = (myPartyId ?? "").isNotEmpty;

                      return StreamBuilder<MeetupRequestState?>(
                        stream: meetupStream,
                        builder: (context, meetupSnap) {
                          final meetupState = meetupSnap.data;
                          final Duration? declineLeft = MeetupService.instance
                              .declineCooldownLeftFromState(meetupState);
                          final bool cooling =
                              (declineLeft != null &&
                              declineLeft > Duration.zero);

                          return StreamBuilder<
                            DocumentSnapshot<Map<String, dynamic>>
                          >(
                            stream: chatDocStream,
                            builder: (context, chatSnap) {
                              ChatGateStatus? gate;
                              bool canReadChatMessages = false;
                              if (chatSnap.data != null &&
                                  chatSnap.data!.exists) {
                                final chatData = chatSnap.data!.data();
                                gate = ChatGateStatus.fromChatDoc(chatData);
                                final participants =
                                    chatData?["participants"] as List<dynamic>?;
                                canReadChatMessages =
                                    participants?.contains(myUid) == true;
                              }

                              final bool chatDeclined =
                                  (gate?.isDeclined ?? false);

                              final VoidCallback? onTap =
                                  (openingThis || cooling || chatDeclined)
                                  ? null
                                  : () => _openChat(otherUid: c.uid);

                              Widget right;
                              if (openingThis) {
                                right = const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                );
                              } else if (chatId != null) {
                                final inline = _inlineGateActions(
                                  chatId: chatId,
                                  otherUid: c.uid,
                                  myUid: myUid,
                                  gate: gate,
                                  cooling: cooling,
                                  openingThis: openingThis,
                                );
                                if (inline is! SizedBox) {
                                  right = inline;
                                } else if (chatDeclined) {
                                  right = Icon(
                                    Icons.block_flipped,
                                    color: cs.onSurface.withValues(alpha: 0.75),
                                  );
                                } else if (cooling) {
                                  right = Icon(
                                    Icons.lock_clock,
                                    color: cs.onSurface.withValues(alpha: 0.75),
                                  );
                                } else if (canReadChatMessages) {
                                  right = StreamBuilder<int>(
                                    stream: UnreadCounterService.instance
                                        .unreadCount(chatId, myUid),
                                    builder: (context, s) {
                                      final n = s.data ?? 0;
                                      if (n <= 0) {
                                        return Icon(
                                          Icons.chat_bubble_outline,
                                          color: cs.onSurface.withValues(
                                            alpha: 0.75,
                                          ),
                                        );
                                      }
                                      return CircleAvatar(
                                        radius: 12,
                                        backgroundColor: cs.primary.withValues(
                                          alpha: 0.22,
                                        ),
                                        child: Text(
                                          n.toString(),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurface,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                } else {
                                  right = Icon(
                                    Icons.chat_bubble_outline,
                                    color: cs.onSurface.withValues(alpha: 0.75),
                                  );
                                }
                              } else {
                                right = Icon(
                                  Icons.chat_bubble_outline,
                                  color: cs.onSurface.withValues(alpha: 0.75),
                                );
                              }

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 7,
                                  horizontal: 6,
                                ),
                                child: ProxGlassCard(
                                  onTap: onTap,
                                  highlight: isActivePeer
                                      ? const Color(0xFF22DE74)
                                      : isBiz
                                      ? const Color(0xFFFF8A3D)
                                      : cs.primary,
                                  glow: isActivePeer
                                      ? const Color(0xFF22DE74)
                                      : isBiz
                                      ? const Color(0xFFFF8A3D)
                                      : cs.primary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: StreamBuilder<UserProfile?>(
                                    stream: _profileStreamForCandidate(c.uid),
                                    builder: (context, ps) {
                                      final p = ps.data;
                                      final photoUrl = p?.photoUrl?.trim() ?? "";
                                      final name = ProxIdentityPolicy.displayName(
                                        uid: c.uid,
                                        profile: p,
                                        isPartyScope: isPartyScope,
                                      );

                                      return Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundImage: photoUrl.isNotEmpty
                                                ? NetworkImage(photoUrl)
                                                : null,
                                            child: photoUrl.isEmpty
                                                ? const Icon(
                                                    Icons.person,
                                                    size: 18,
                                                  )
                                                : null,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: FutureBuilder<List<String>>(
                                              future: _sharedKeywordsForCandidate(
                                                c.uid,
                                              ),
                                              builder: (context, kwSnap) {
                                                final List<String>
                                                matchedKeywords =
                                                    (kwSnap.data ??
                                                            const <String>[])
                                                        .take(5)
                                                        .toList(
                                                          growable: false,
                                                        );

                                                return Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            name,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: Theme.of(context)
                                                                .textTheme
                                                                .titleMedium
                                                                ?.copyWith(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                  color: cs
                                                                      .onSurface
                                                                      .withValues(
                                                                        alpha:
                                                                            0.92,
                                                                      ),
                                                                ),
                                                          ),
                                                        ),
                                                        if (isBiz) ...[
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          _chip(
                                                            (avail != null &&
                                                                    avail <= 0)
                                                                ? "Business  Now"
                                                                : "Business",
                                                            strong: true,
                                                          ),
                                                        ],
                                                        if (_isNewUser(p)) ...[
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          _chip(
                                                            "New User",
                                                            strong: true,
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                    if (matchedKeywords
                                                        .isNotEmpty) ...[
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        "Matches on",
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .labelSmall
                                                            ?.copyWith(
                                                              color: cs
                                                                  .onSurface
                                                                  .withValues(
                                                                    alpha: 0.65,
                                                                  ),
                                                            ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Wrap(
                                                        spacing: 6,
                                                        runSpacing: 6,
                                                        crossAxisAlignment:
                                                            WrapCrossAlignment
                                                                .center,
                                                        children: [
                                                          for (final kw
                                                              in matchedKeywords)
                                                            _matchChip(kw),
                                                        ],
                                                      ),
                                                    ],
                                                    const SizedBox(height: 6),
                                                    Wrap(
                                                      spacing: 8,
                                                      runSpacing: 8,
                                                      crossAxisAlignment:
                                                          WrapCrossAlignment
                                                              .center,
                                                      children: [
                                                        if (isActivePeer)
                                                          _chip(
                                                            "Active ${_fmtMMSS(activeTimeLeft ?? Duration.zero)}",
                                                            strong: true,
                                                          ),
                                                        if (distLabel != null)
                                                          _chip(distLabel),
                                                        _gateChipFrom(
                                                          gate,
                                                          myUid,
                                                          cooling: cooling,
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          right,
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ProxNebulaBackground(
        child: Stack(
          children: [
            StreamBuilder<UserSettings>(
              stream: UserSettingsService.instance.watch(),
              builder: (context, ssnap) {
                final settings =
                    ssnap.data ?? UserSettingsService.instance.current;
                final discovery = settings.matchDiscovery;
                final simpleMode =
                    settings.simpleModeEnabled && !settings.alwaysUseNormalMode;
                if (simpleMode) {
                  _enforceSimpleDiscoveryDefaults(discovery);
                }
                final incomingLeft = _incomingDeadline == null
                    ? null
                    : _incomingDeadline!.difference(DateTime.now());
                final radiusMiles = math.max(
                  0.1,
                  MatchingRuntimeService.instance.effectiveRadiusMiles(
                    discovery,
                  ),
                );
                _ensureNearbyStream(radiusMiles);

                return StreamBuilder<String?>(
                  stream: PartyModeService.instance.watchCurrentPartyId(),
                  builder: (context, partyScopeSnap) {
                    final myPartyId = partyScopeSnap.data;
                    return StreamBuilder<List<PartyMemberEntry>>(
                      stream: PartyService.instance.watchMyPartyEntries(),
                      builder: (context, partySnap) {
                        final partyMembers =
                            partySnap.data ?? const <PartyMemberEntry>[];
                        final partyMemberUids = partyMembers
                            .map((e) => e.otherUid.trim())
                            .where((uid) => uid.isNotEmpty)
                            .toSet();

                        return CustomScrollView(
                          physics: const ClampingScrollPhysics(),
                          slivers: [
                            SliverAppBar(
                              pinned: true,
                              floating: false,
                              backgroundColor: Colors.transparent,
                              surfaceTintColor: Colors.transparent,
                              elevation: 0,
                              expandedHeight: 86,
                              flexibleSpace: ClipRRect(
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 18,
                                    sigmaY: 18,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: cs.surface.withValues(alpha: 0.08),
                                      border: Border(
                                        bottom: BorderSide(
                                          color: cs.outline.withValues(
                                            alpha: 0.12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              title: const Text("Nearby"),
                              actions: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: Row(
                                    children: [
                                      GestureDetector(
                                        onTap: _showMatchFoundForTop,
                                        child: ProxGlass(
                                          radius: 999,
                                          blurSigma: 14,
                                          fillOpacity: 0.10,
                                          borderOpacity: 0.16,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.auto_awesome,
                                                size: 18,
                                                color: cs.onSurface.withValues(
                                                  alpha: 0.85,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                "Match",
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: cs.onSurface
                                                          .withValues(
                                                            alpha: 0.85,
                                                          ),
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (!simpleMode) ...[
                                        const SizedBox(width: 10),
                                        GestureDetector(
                                          onTap: _openModeChooser,
                                          child: ProxGlass(
                                            radius: 999,
                                            blurSigma: 14,
                                            fillOpacity: 0.10,
                                            borderOpacity: 0.16,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.tune,
                                                  size: 18,
                                                  color: cs.onSurface
                                                      .withValues(alpha: 0.85),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  "Mode",
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: cs.onSurface
                                                            .withValues(
                                                              alpha: 0.85,
                                                            ),
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (discovery.modeKind ==
                                          MatchingModeKind.treasureHunt) ...[
                                        const SizedBox(width: 10),
                                        GestureDetector(
                                          onTap: _openTreasureHunt,
                                          child: ProxGlass(
                                            radius: 999,
                                            blurSigma: 14,
                                            fillOpacity: 0.10,
                                            borderOpacity: 0.16,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.explore,
                                                  size: 18,
                                                  color: cs.onSurface
                                                      .withValues(alpha: 0.85),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  "Compass",
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: cs.onSurface
                                                            .withValues(
                                                              alpha: 0.85,
                                                            ),
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (simpleMode)
                              _buildSimpleSearchSettings(discovery, cs),
                            _buildNearbyStatusPanel(discovery, cs, radiusMiles),
                            _buildProxCircleActivatorCard(discovery, cs),
                            if (discovery.modeKind == MatchingModeKind.normal &&
                                discovery.normalMode ==
                                    NormalMatchMode.active &&
                                incomingLeft != null &&
                                incomingLeft > Duration.zero)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    0,
                                    18,
                                    8,
                                  ),
                                  child: Text(
                                    "Accept pending chat in ${_fmtMMSS(incomingLeft)} or Active auto-switches to Passive for 10:00.",
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: const Color(0xFFDE5353),
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ),
                            SliverFillRemaining(
                              hasScrollBody: true,
                              child: _buildNearbyCardsScrollableArea(
                                discovery: discovery,
                                myPartyId: myPartyId,
                                partyMemberUids: partyMemberUids,
                                cs: cs,
                                bottomInset: bottomInset,
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
            if (_opening)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: Container(
                    alignment: Alignment.bottomCenter,
                    padding: EdgeInsets.only(bottom: 14 + bottomInset),
                    child: ProxGlass(
                      radius: 999,
                      blurSigma: 18,
                      fillOpacity: 0.12,
                      borderOpacity: 0.16,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text("Opening chat..."),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProxHoldRingPainter extends CustomPainter {
  const _ProxHoldRingPainter({required this.progress01, required this.color});

  final double progress01;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final double p = progress01.clamp(0.0, 1.0);

    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = color.withValues(alpha: 0.24)
      ..strokeCap = StrokeCap.round;

    final Paint progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = color.withValues(alpha: 0.95)
      ..strokeCap = StrokeCap.round;

    final Offset c = rect.center;
    final double r = (size.shortestSide / 2) - 3;
    canvas.drawCircle(c, r, track);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      (2 * math.pi) * p,
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(covariant _ProxHoldRingPainter oldDelegate) {
    return oldDelegate.progress01 != progress01 || oldDelegate.color != color;
  }
}
