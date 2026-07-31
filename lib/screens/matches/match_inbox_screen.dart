import "dart:async";
import "dart:math" as math;
import "dart:ui";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/screens/discovery/matching_mode_screen.dart";
import "package:prox/screens/treasure_hunt/treasure_hunt_screen.dart";
import "package:prox/services/chat/chat_gate_service.dart";
import "package:prox/services/chat/chat_thread_service.dart";
import "package:prox/services/chat/unread_counter_service.dart";
import "package:prox/services/geoquery_service.dart";
import "package:prox/services/matching/active_mode_policy_service.dart";
import "package:prox/services/matching/matching_mode_service.dart";
import "package:prox/services/matching/matching_runtime_service.dart";
import "package:prox/services/matching/match_pipeline.dart";
import "package:prox/services/meetup_service.dart";
import "package:prox/services/party_mode_service.dart";
import "package:prox/services/presence_writer.dart";
import "package:prox/services/user_profile_service.dart";
import "package:prox/services/user_settings_service.dart";
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

class _MatchInboxScreenState extends State<MatchInboxScreen>
    with SingleTickerProviderStateMixin {
  // Guardrail: this anchor marks the Nearby Prox Circle activation control.
  // Keep this widget in the tree; tests enforce this key's presence.
  static const Key _kNearbyProxCircleAnchorKey = ValueKey<String>(
    "nearby_prox_circle_anchor",
  );

  bool _opening = false;
  String _openingUid = "";

  static const Duration _kHoldToActivateDuration = Duration(seconds: 3);
  static const Duration _kStartupTapOffWindow = Duration(seconds: 10);
  static bool _didApplyNearbyBootDefault = false;

  String _topUid = "";
  String _topDistanceLabel = "Nearby";
  List<String> _topKeywords = const <String>[];

  // Ticks UI so decline cooldown chips count down live.
  // Kept intentionally low-frequency to reduce rebuild cost.
  Timer? _uiTick;
  Timer? _holdTick;
  Timer? _startupWindowTick;
  double _holdProgress01 = 0.0;
  bool _holdTriggeredActivation = false;
  bool _cycleUnlocked = false;
  bool _startupOffPromptActive = true;
  late final DateTime _startupOffTapUntil;
  late final AnimationController _orbitController;
  Duration? _orbitDuration;
  Stream<List<NearbyDoc>>? _nearbyStream;
  double? _nearbyStreamRadiusMiles;
  StreamSubscription<DateTime?>? _incomingDeadlineSub;
  DateTime? _incomingDeadline;

  @override
  void initState() {
    super.initState();
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
      unawaited(ChatGateService.instance
          .enforceExpiredIncomingRequestsIfNeeded(forUid: uid));
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
    final bool showActiveTag = discovery.modeKind == MatchingModeKind.normal &&
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
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
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
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: cs.surface.withValues(alpha: 0.18),
                          ),
                          child: Text(
                            "Active",
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
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
    _uiTick?.cancel();
    _holdTick?.cancel();
    _startupWindowTick?.cancel();
    _orbitController.dispose();
    _incomingDeadlineSub?.cancel();
    super.dispose();
  }

  bool get _startupOffWindowOpen => DateTime.now().isBefore(_startupOffTapUntil);

  Duration get _startupOffWindowLeft {
    final d = _startupOffTapUntil.difference(DateTime.now());
    return d > Duration.zero ? d : Duration.zero;
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

  void _setNormalMode(NormalMatchMode mode) {
    final current = MatchingModeService.instance.discovery.normalMode;
    if (current == mode) return;
    MatchingModeService.instance.setMode(
      mode == NormalMatchMode.active
          ? ProxMatchingMode.active
          : ProxMatchingMode.passive,
    );
    if (mode == NormalMatchMode.active) {
      _cycleUnlocked = true;
    }
    _snack("Normal mode: ${mode == NormalMatchMode.active ? "Active" : "Passive"}.");
    if (mounted) setState(() {});
  }

  void _cycleModeKindFromCircle(MatchDiscoverySettings discovery) {
    if (!_cycleUnlocked) return;

    const List<MatchingModeKind> order = <MatchingModeKind>[
      MatchingModeKind.normal,
      MatchingModeKind.listen,
      MatchingModeKind.treasureHunt,
      MatchingModeKind.travel,
      MatchingModeKind.off,
    ];

    final int i = order.indexOf(discovery.modeKind);
    final int nextIndex = i < 0 ? 0 : (i + 1) % order.length;
    final MatchingModeKind next = order[nextIndex];

    MatchingModeService.instance.setModeKind(next);
    _snack("Mode: ${_modeChipLabel(MatchingModeService.instance.discovery)}");
    if (mounted) setState(() {});
  }

  void _onCircleTap(MatchDiscoverySettings discovery) {
    final bool isNormalPassive =
        discovery.modeKind == MatchingModeKind.normal &&
            discovery.normalMode == NormalMatchMode.passive;

    if (!_cycleUnlocked) {
      if (discovery.modeKind == MatchingModeKind.off && _startupOffWindowOpen) {
        MatchingModeService.instance.setModeKind(MatchingModeKind.normal);
        MatchingModeService.instance.setMode(ProxMatchingMode.passive);
        _snack("Normal Passive restored.");
        if (mounted) setState(() {});
        return;
      }
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

  void _turnMatchingOffFromActive() {
    MatchingModeService.instance.setModeKind(MatchingModeKind.off);
    _startupOffPromptActive = false;
    if (!mounted) return;
    setState(() {});
  }

  void _onHoldProxCircle(MatchDiscoverySettings discovery) {
    if (discovery.modeKind != MatchingModeKind.normal) {
      _snack("Set mode to Normal first.");
      return;
    }
    if (discovery.normalMode == NormalMatchMode.active) return;

    if (discovery.isActiveLocked) {
      final left = Duration(
        milliseconds: (discovery.activeLockUntilEpochMs -
                DateTime.now().millisecondsSinceEpoch)
            .clamp(0, 1 << 30),
      );
      _snack("Active is locked for ${_fmtMMSS(left)}.");
      return;
    }

    _holdTick?.cancel();
    _holdProgress01 = 0.0;
    _holdTriggeredActivation = true;
    _startupOffPromptActive = false;

    MatchingModeService.instance.setMode(ProxMatchingMode.active);
    _cycleUnlocked = true;
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
      final double p =
          (elapsedMs / _kHoldToActivateDuration.inMilliseconds).clamp(0.0, 1.0);
      setState(() {
        _holdProgress01 = p;
      });
      if (p >= 1.0) {
        _onHoldProxCircle(discovery);
      }
    });
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
      final String predictedChatId =
          ChatThreadService.instance.chatIdFor(myUid, otherUid);

      final Duration? left =
          await MeetupService.instance.declineCooldownLeft(predictedChatId);
      if (left != null && left > Duration.zero) {
        if (!mounted) return;
        _snack("Meetup declined - try again in ${_fmtMMSS(left)}.");
        return;
      }

      final chatId = await ChatThreadService.instance
          .ensureChat(myUid: myUid, otherUid: otherUid)
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;
      Navigator.of(context).pushNamed(
        "/chat",
        arguments: {"chatId": chatId, "otherUid": otherUid},
      );
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TreasureHuntScreen()),
    );
  }

  Future<void> _showMatchFoundForTop() async {
    final uid = _topUid.trim();
    if (uid.isEmpty) {
      _snack("No matches nearby yet.");
      return;
    }
    if (!mounted) return;

    final List<String> keywords = (_topKeywords.isNotEmpty)
        ? _topKeywords
        : const <String>["Shared interest", "Nearby", "Right now"];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => MatchFoundSheet(
        distanceLabel:
            _topDistanceLabel.trim().isEmpty ? "Nearby" : _topDistanceLabel,
        keywords: keywords,
        onIgnore: () => Navigator.of(context).pop(),
        onSayHi: () {
          Navigator.of(context).pop();
          _openChat(otherUid: uid);
        },
      ),
    );
  }

  Widget _chip(String text, {bool strong = false}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outline.withValues(alpha: 0.16)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color:
                  strong ? cs.onSurface : cs.onSurface.withValues(alpha: 0.72),
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            ),
      ),
    );
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

    return nearby.where((d) {
      if (!d.isBusiness) return false;
      if (!immediateOnly) return true;
      final mins = d.availabilityMinutes;
      return mins != null && mins <= 0;
    }).toList(growable: false);
  }

  static List<String> _extractKeywordsFromCandidate(dynamic c) {
    try {
      final dynamic prof = c.profile;
      if (prof is Map) {
        final raw = prof["keywords"];
        if (raw is List) {
          return raw
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList(growable: false);
        }
      }
    } catch (_) {}
    return const <String>[];
  }

  void _captureTopCandidate(List<dynamic> items) {
    if (items.isEmpty) return;

    final dynamic c0 = items.first;
    final String uid = (c0.uid ?? "").toString();
    if (uid.isEmpty) return;

    final double? miles =
        (c0.distanceMiles is num) ? (c0.distanceMiles as num).toDouble() : null;
    final String label = (miles == null)
        ? "Nearby"
        : (ProxDistanceFormat.bucketMilesOrNull(miles) ?? "Nearby");

    final List<String> kw = _extractKeywordsFromCandidate(c0);
    final List<String> top3 = kw.take(3).toList(growable: false);

    final bool changed = uid != _topUid ||
        label != _topDistanceLabel ||
        !_listEq(top3, _topKeywords);

    if (changed) {
      if (!mounted) return;
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

  bool _isLocationBlockingError(String err) {
    final e = err.toLowerCase();
    return e.contains("permission") ||
        e.contains("services off") ||
        e.contains("blocked") ||
        e.contains("timeout") ||
        e.contains("no /users/") ||
        e.contains("missing geopoint");
  }

  void _ensureNearbyStream(double radiusMiles) {
    final current = _nearbyStreamRadiusMiles;
    if (_nearbyStream != null &&
        current != null &&
        (current - radiusMiles).abs() < 0.001) {
      return;
    }
    _nearbyStreamRadiusMiles = radiusMiles;
    _nearbyStream = GeoQueryService.instance.streamNearby(
      center: null,
      radiusMiles: radiusMiles,
    );
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
    final bool showActiveDot = discovery.modeKind == MatchingModeKind.normal &&
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
              onTapDown:
                  canHoldToActivate ? (_) => _beginHoldToActivate(discovery) : null,
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
                          color: Color.lerp(
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
                              0.82 + (0.18 * math.sin(_orbitController.value * math.pi * 2));
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
                        border: Border.all(
                          color: accent,
                          width: 4,
                        ),
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
                                                        math.sin(
                                                          _orbitController.value *
                                                              math.pi *
                                                              2,
                                                        ).abs()));
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
                                            child: ProxLogoMark(size: 92),
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
                                            color: accent.withValues(alpha: 0.92),
                                          ),
                                    ),
                                    if (isNormalMode)
                                      Text(
                                        discovery.normalMode == NormalMatchMode.active
                                            ? "ACTIVE"
                                            : "PASSIVE",
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.8,
                                              color: cs.onSurface
                                                  .withValues(alpha: 0.78),
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
                                            padding: const EdgeInsets.only(top: 14),
                                            child: Container(
                                              width: 10,
                                              height: 10,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: accent.withValues(alpha: 0.92),
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
                              if (discovery.modeKind == MatchingModeKind.treasureHunt &&
                                  animateOrbit)
                                Positioned.fill(
                                  child: Transform.rotate(
                                    angle: -angle,
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: Padding(
                                        padding: const EdgeInsets.only(bottom: 13),
                                        child: Icon(
                                          Icons.explore,
                                          size: 16,
                                          color: accent.withValues(alpha: 0.9),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (discovery.modeKind == MatchingModeKind.travel &&
                                  animateOrbit)
                                Positioned.fill(
                                  child: Transform.rotate(
                                    angle: angle * 1.35,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Padding(
                                        padding: const EdgeInsets.only(left: 12),
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: accent.withValues(alpha: 0.86),
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
                                          0.42 + (0.58 * math.sin(_orbitController.value * math.pi * 2).abs());
                                      return Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: List<Widget>.generate(5, (i) {
                                          final h = 4 + ((i.isEven ? p : 1 - p) * 10);
                                          return Container(
                                            width: 4,
                                            height: h,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(999),
                                              color: accent.withValues(alpha: 0.88),
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
              _cycleUnlocked
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
              SegmentedButton<NormalMatchMode>(
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
            ],
            if (isListenMode) ...[
              const SizedBox(height: 10),
              SegmentedButton<ListenMatchRole>(
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: cs.surface.withValues(alpha: 0.16),
                    border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
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
    required ColorScheme cs,
    required double bottomInset,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        bottom: 16 + bottomInset,
      ),
      child: StreamBuilder<List<NearbyDoc>>(
        stream: _nearbyStream,
        builder: (context, snap) {
          final rawNearby = snap.data ?? const <NearbyDoc>[];
          final nearby = _applyBusinessFilter(rawNearby, discovery);

          return FutureBuilder<List<NearbyDoc>>(
            future: MatchingRuntimeService.instance.filterByMode(nearby),
            builder: (context, filteredSnap) {
              if (!filteredSnap.hasData) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 26),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.explore_outlined, color: cs.primary, size: 34),
                        const SizedBox(height: 8),
                        Text(
                          "Loading nearby matches...",
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                );
              }

              final modeFilteredNearby = filteredSnap.data ?? const <NearbyDoc>[];

              return FutureBuilder(
                future: MatchPipeline.instance.buildCandidates(
                  nearby: modeFilteredNearby,
                  myPartyId: myPartyId ?? "",
                ),
                builder: (context, rankedSnap) {
                  if (!rankedSnap.hasData) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  final items = rankedSnap.data!;
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
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "No one nearby",
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.72),
                                  ),
                            ),
                            const SizedBox(height: 12),
                            const ProxLogoMark(size: 36),
                          ],
                        ),
                      ),
                    );
                  }

                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _captureTopCandidate(items));

                  return ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final c = items[i];

                      final String myUid = FirebaseAuth.instance.currentUser?.uid ?? "";
                      final String? chatId = myUid.isEmpty
                          ? null
                          : ChatThreadService.instance.chatIdFor(myUid, c.uid);

                      final bool openingThis = _opening && _openingUid == c.uid;

                      final Stream<DocumentSnapshot<Map<String, dynamic>>>
                          chatDocStream = (chatId == null)
                              ? const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty()
                              : FirebaseFirestore.instance
                                  .collection("chats")
                                  .doc(chatId)
                                  .snapshots();

                      final Stream<MeetupRequestState?> meetupStream =
                          (chatId == null)
                              ? const Stream<MeetupRequestState?>.empty()
                              : MeetupService.instance.watchRequestState(chatId: chatId);

                      NearbyDoc? nd;
                      for (final d in modeFilteredNearby) {
                        if (d.uid == c.uid) {
                          nd = d;
                          break;
                        }
                      }
                      final bool isBiz = nd?.isBusiness == true;
                      final int? avail = nd?.availabilityMinutes;

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
                              (declineLeft != null && declineLeft > Duration.zero);

                          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            stream: chatDocStream,
                            builder: (context, chatSnap) {
                              ChatGateStatus? gate;
                              if (chatSnap.data != null && chatSnap.data!.exists) {
                                gate = ChatGateStatus.fromChatDoc(
                                  chatSnap.data!.data(),
                                );
                              }

                              final bool chatDeclined = (gate?.isDeclined ?? false);

                              final VoidCallback? onTap =
                                  (openingThis || cooling || chatDeclined)
                                      ? null
                                      : () => _openChat(otherUid: c.uid);

                              Widget right;
                              if (openingThis) {
                                right = const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
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
                                } else {
                                  right = StreamBuilder<int>(
                                    stream: UnreadCounterService.instance
                                        .unreadCount(chatId, myUid),
                                    builder: (context, s) {
                                      final n = s.data ?? 0;
                                      if (n <= 0) {
                                        return Icon(
                                          Icons.chat_bubble_outline,
                                          color: cs.onSurface.withValues(alpha: 0.75),
                                        );
                                      }
                                      return CircleAvatar(
                                        radius: 12,
                                        backgroundColor:
                                            cs.primary.withValues(alpha: 0.22),
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
                                  highlight:
                                      isBiz ? const Color(0xFFFF8A3D) : cs.primary,
                                  glow:
                                      isBiz ? const Color(0xFFFF8A3D) : cs.primary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      StreamBuilder<UserProfile?>(
                                        stream: UserProfileService.instance
                                            .watchProfile(c.uid),
                                        builder: (context, ps) {
                                          final p = ps.data;
                                          final photoUrl =
                                              p?.photoUrl?.trim() ?? "";
                                          return CircleAvatar(
                                            radius: 18,
                                            backgroundImage: photoUrl.isNotEmpty
                                                ? NetworkImage(photoUrl)
                                                : null,
                                            child: photoUrl.isEmpty
                                                ? const Icon(Icons.person, size: 18)
                                                : null,
                                          );
                                        },
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: StreamBuilder<UserProfile?>(
                                          stream: UserProfileService.instance
                                              .watchProfile(c.uid),
                                          builder: (context, ps) {
                                            final p = ps.data;
                                            final name = ProxIdentityPolicy.displayName(
                                              uid: c.uid,
                                              profile: p,
                                              isPartyScope: isPartyScope,
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
                                                            TextOverflow.ellipsis,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .titleMedium
                                                            ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight.w800,
                                                              color: cs.onSurface
                                                                  .withValues(
                                                                      alpha: 0.92),
                                                            ),
                                                      ),
                                                    ),
                                                    if (isBiz) ...[
                                                      const SizedBox(width: 8),
                                                      _chip(
                                                        (avail != null &&
                                                                avail <= 0)
                                                            ? "Business  Now"
                                                            : "Business",
                                                        strong: true,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  crossAxisAlignment:
                                                      WrapCrossAlignment.center,
                                                  children: [
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
                final incomingLeft = _incomingDeadline == null
                    ? null
                    : _incomingDeadline!.difference(DateTime.now());
                final radiusMiles = math.max(
                  0.1,
                  MatchingRuntimeService.instance.effectiveRadiusMiles(discovery),
                );
                _ensureNearbyStream(radiusMiles);

                return StreamBuilder<String?>(
                  stream: PartyModeService.instance.watchCurrentPartyId(),
                  builder: (context, partyScopeSnap) {
                    final myPartyId = partyScopeSnap.data;

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
                              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: cs.surface.withValues(alpha: 0.08),
                                  border: Border(
                                    bottom: BorderSide(
                                      color: cs.outline.withValues(alpha: 0.12),
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
                                            color: cs.onSurface
                                                .withValues(alpha: 0.85),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Match",
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  color: cs.onSurface
                                                      .withValues(alpha: 0.85),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
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
                                                  fontWeight: FontWeight.w700,
                                                  color: cs.onSurface
                                                      .withValues(alpha: 0.85),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
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
                                                    fontWeight: FontWeight.w700,
                                                    color: cs.onSurface
                                                        .withValues(
                                                            alpha: 0.85),
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
                        _buildNearbyStatusPanel(discovery, cs, radiusMiles),
                        _buildProxCircleActivatorCard(discovery, cs),
                        if (discovery.modeKind == MatchingModeKind.normal &&
                            discovery.normalMode == NormalMatchMode.active &&
                            incomingLeft != null &&
                            incomingLeft > Duration.zero)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                              child: Text(
                                "Accept pending chat in ${_fmtMMSS(incomingLeft)} or Active auto-switches to Passive for 10:00.",
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: const Color(0xFFDE5353),
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ),
                        if (discovery.modeKind == MatchingModeKind.normal &&
                            discovery.normalMode == NormalMatchMode.passive &&
                            discovery.isActiveLocked)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                              child: Text(
                                "Active lock remaining: ${_fmtMMSS(Duration(milliseconds: (discovery.activeLockUntilEpochMs - DateTime.now().millisecondsSinceEpoch).clamp(0, 1 << 30)))}",
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: const Color(0xFFDE5353),
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: AnimatedBuilder(
                              animation: GeoQueryService.instance.debug,
                              builder: (context, _) {
                                final err = GeoQueryService
                                    .instance.debug.lastError
                                    .trim();
                                if (err.isEmpty) return const SizedBox.shrink();
                                if (!_isLocationBlockingError(err))
                                  return const SizedBox.shrink();

                                return LocationIssueBanner(
                                  hint: err,
                                  onRetry: () async {
                                    await PresenceWriter.instance
                                        .forceWrite(reason: "nearby_retry");
                                    if (!mounted) return;
                                    _snack("Retry requested.");
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                        SliverFillRemaining(
                          hasScrollBody: true,
                          child: _buildNearbyCardsScrollableArea(
                            discovery: discovery,
                            myPartyId: myPartyId,
                            cs: cs,
                            bottomInset: bottomInset,
                          ),
                        ),
                      ],
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
                          horizontal: 14, vertical: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2)),
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
  const _ProxHoldRingPainter({
    required this.progress01,
    required this.color,
  });

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

