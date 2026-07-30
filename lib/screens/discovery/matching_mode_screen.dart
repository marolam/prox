import "package:flutter/material.dart";
import "package:firebase_auth/firebase_auth.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/screens/services/match_settings_service.dart";
import "package:prox/services/matching/matching_mode_service.dart";
import "package:prox/services/monetization_service.dart";
import "package:prox/services/user_profile_service.dart";
import "package:prox/services/user_settings_service.dart";
import "package:prox/widgets/prox_background.dart";
import "package:prox/widgets/prox_glass.dart";

class MatchingModeScreen extends StatefulWidget {
  const MatchingModeScreen({
    super.key,
    this.focusRadius = false,
  });

  final bool focusRadius;

  @override
  State<MatchingModeScreen> createState() => _MatchingModeScreenState();
}

class _MatchingModeScreenState extends State<MatchingModeScreen> {
  late MatchingModeKind _kind;
  late NormalMatchMode _normalMode;
  late ListenMatchRole _listenRole;
  late double _radiusMiles;
  late double _treasureRadius;
  bool _businessOnly = false;
  KeywordMatchMode _keywordMode = KeywordMatchMode.similar;
  bool _activeLocked = false;
  bool _highRadiusUnlocked = false;
  bool _singleKeywordUnlocked = false;
  bool _reciprocalUnlocked = false;
  bool _keywordChainUnlocked = false;
  int _keywordCount = 0;

  @override
  void initState() {
    super.initState();
    final d = MatchingModeService.instance.discovery;
    _kind = d.modeKind;
    _normalMode = d.normalMode;
    _listenRole = d.listenRole;
    _radiusMiles = d.radiusMiles;
    _treasureRadius = d.treasureRadiusMiles;
    _businessOnly = d.businessOnly;
    _keywordMode = d.keywordMode;
    _activeLocked = d.isActiveLocked;
    _highRadiusUnlocked = d.highRadiusUnlocked;
    _singleKeywordUnlocked = d.singleKeywordMatchUnlocked;
    _reciprocalUnlocked = d.reciprocalMatchUnlocked;
    _keywordChainUnlocked = d.keywordChainUnlocked;

    // ignore: discarded_futures
    _refreshGuidanceContext();
  }

  Future<void> _refreshGuidanceContext() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.trim().isEmpty) return;

    final entitlements =
        await MonetizationService.instance.getEntitlementsMap(uid: uid);
    final unlocked = entitlements["highRadiusUnlocked"] == true;
    final singleKeywordUnlocked =
        entitlements["singleKeywordMatchModeUnlocked"] == true;
    final reciprocalUnlocked =
        entitlements["reciprocalKeywordMatchModeUnlocked"] == true;
    final keywordChainUnlocked =
        entitlements["keywordChainMatchModeUnlocked"] == true;
    UserSettingsService.instance.setHighRadiusUnlocked(unlocked);
    UserSettingsService.instance
        .setSingleKeywordMatchUnlocked(singleKeywordUnlocked);
    UserSettingsService.instance.setReciprocalMatchUnlocked(reciprocalUnlocked);
    UserSettingsService.instance.setKeywordChainUnlocked(keywordChainUnlocked);

    final profile = await UserProfileService.instance.getProfileOnce(uid);
    final keywordCount = _estimateKeywordCount(profile);

    if (!mounted) return;
    setState(() {
      _highRadiusUnlocked = unlocked;
      _singleKeywordUnlocked = singleKeywordUnlocked;
      _reciprocalUnlocked = reciprocalUnlocked;
      _keywordChainUnlocked = keywordChainUnlocked;
      _keywordCount = keywordCount;
    });
  }

  bool _isKeywordModeUnlocked(KeywordMatchMode mode) {
    switch (mode) {
      case KeywordMatchMode.singleKeyword:
        return _singleKeywordUnlocked;
      case KeywordMatchMode.reciprocalOpposite:
        return _reciprocalUnlocked;
      case KeywordMatchMode.keywordChain:
        return _keywordChainUnlocked;
      case KeywordMatchMode.similar:
      case KeywordMatchMode.strict:
        return true;
    }
  }

  String _keywordModeLabel(KeywordMatchMode mode) {
    switch (mode) {
      case KeywordMatchMode.similar:
        return "Similar";
      case KeywordMatchMode.strict:
        return "Strict";
      case KeywordMatchMode.singleKeyword:
        return "Single Keyword";
      case KeywordMatchMode.reciprocalOpposite:
        return "Reciprocal Opposite";
      case KeywordMatchMode.keywordChain:
        return "Keyword Chain";
    }
  }

  List<DropdownMenuItem<KeywordMatchMode>> _keywordModeItems() {
    const allModes = <KeywordMatchMode>[
      KeywordMatchMode.similar,
      KeywordMatchMode.strict,
      KeywordMatchMode.singleKeyword,
      KeywordMatchMode.reciprocalOpposite,
      KeywordMatchMode.keywordChain,
    ];

    return allModes.map((mode) {
      final unlocked = _isKeywordModeUnlocked(mode);
      final suffix = unlocked ? "" : " (Store unlock required)";
      return DropdownMenuItem<KeywordMatchMode>(
        value: mode,
        enabled: unlocked,
        child: Text("${_keywordModeLabel(mode)}$suffix"),
      );
    }).toList(growable: false);
  }

  int _estimateKeywordCount(UserProfile? profile) {
    if (profile == null) return 0;
    final items = <String>{
      ...profile.searchingFor,
      ...profile.canProvide,
      if ((profile.searching ?? "").trim().isNotEmpty)
        profile.searching!.trim(),
      if ((profile.providing ?? "").trim().isNotEmpty)
        profile.providing!.trim(),
    };

    return items.where((e) => e.trim().isNotEmpty).length;
  }

  List<String> _buildGuidance(double maxAllowedRadius) {
    final suggestions = <String>[];

    if (maxAllowedRadius <= 15.0 &&
        _kind == MatchingModeKind.normal &&
        _normalMode == NormalMatchMode.passive) {
      suggestions.add(
          "Unlock High Radius in the Prox Store to extend Business Passive search up to 30 mi.");
    }

    if (_radiusMiles > 15.0 && _keywordCount < 3) {
      suggestions.add(
          "Add at least 3 clear search/provide keywords for better far-radius match quality.");
    }

    if (_kind == MatchingModeKind.travel) {
      suggestions.add(
          "Travel mode is strict. If results are sparse, switch to Normal Passive for broader coverage.");
    }

    if (_kind == MatchingModeKind.listen) {
      suggestions.add(
          "Listen mode only pairs opposite roles. Speak matches Listeners, and Listen matches Speakers.");
    }

    if (_radiusMiles > 15.0) {
      suggestions.add(
          "At very high radius, far profiles are filtered to keyword overlaps to reduce low-intent noise.");
    }

    if (!_singleKeywordUnlocked ||
        !_reciprocalUnlocked ||
        !_keywordChainUnlocked) {
      suggestions.add(
          "Prox Store unlocks additional keyword modes: Single Keyword, Reciprocal Opposite, and Keyword Chain.");
    }

    return suggestions;
  }

  void _setKind(MatchingModeKind kind) {
    setState(() => _kind = kind);
  }

  void _setNormalMode(NormalMatchMode mode) {
    setState(() => _normalMode = mode);
  }

  void _setListenRole(ListenMatchRole role) {
    setState(() => _listenRole = role);
  }

  void _commitAndClose() {
    try {
      final svc = MatchingModeService.instance;
      final effectiveKeywordMode = _isKeywordModeUnlocked(_keywordMode)
          ? _keywordMode
          : KeywordMatchMode.similar;
      final safeRadius = _radiusMiles
          .clamp(MatchDiscoverySettings.minRadiusMiles,
              MatchDiscoverySettings.extendedMaxRadiusMiles)
          .toDouble();
      final safeTreasureRadius = _treasureRadius
          .clamp(MatchDiscoverySettings.minRadiusMiles,
              MatchDiscoverySettings.maxRadiusMiles)
          .toDouble();

      svc.setRadiusMiles(safeRadius);
      svc.setModeKind(_kind);
      svc.setListenRole(_listenRole);
      svc.setTreasureRadiusMiles(safeTreasureRadius);
      MatchSettingsService.instance.setBusinessOnly(_businessOnly);
      MatchSettingsService.instance.setKeywordMode(effectiveKeywordMode);
      if (_kind == MatchingModeKind.normal) {
        svc.setMode(_normalMode == NormalMatchMode.active
            ? ProxMatchingMode.active
            : ProxMatchingMode.passive);
      }
    } catch (_) {
      // Keep the chooser closable even if persistence/network updates fail.
    }

    if (!mounted) return;
    final nav = Navigator.maybeOf(context);
    if (nav != null) {
      nav.maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final blue = cs.primary;
    final orange = const Color(0xFFFF8A3D);
    final green = const Color(0xFF1F9D6D);
    final aqua = const Color(0xFF2AB8A6);
    final red = const Color(0xFFDE5353);
    final maxAllowedRadius = MatchDiscoverySettings.allowedMaxRadiusMiles(
      highRadiusUnlocked: _highRadiusUnlocked,
      businessOnly: _businessOnly,
      modeKind: _kind,
      normalMode: _normalMode,
    );

    if (_radiusMiles > maxAllowedRadius) {
      _radiusMiles = maxAllowedRadius;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ProxNebulaBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        Text(
                          widget.focusRadius
                              ? "Adjust your match radius"
                              : "Choose your matching mode",
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.80),
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 22),
                        ProxGlass(
                          radius: 18,
                          blurSigma: 18,
                          fillOpacity: 0.10,
                          borderOpacity: 0.16,
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Match radius: ${_radiusMiles.toStringAsFixed(1)} mi",
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Slider(
                                value: _radiusMiles,
                                min: MatchDiscoverySettings.minRadiusMiles,
                                max: maxAllowedRadius,
                                divisions: ((maxAllowedRadius -
                                            MatchDiscoverySettings
                                                .minRadiusMiles) *
                                        2)
                                    .round()
                                    .clamp(1, 100),
                                onChanged: (v) =>
                                    setState(() => _radiusMiles = v),
                              ),
                              Text(
                                maxAllowedRadius > 15.0
                                    ? "High-radius unlocked for Business + Passive. Wider radius can return broader, lower-intent results."
                                    : "For performance/cost protection, high radius is capped until High Radius Unlock is active.",
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.72),
                                ),
                              ),
                              ..._buildGuidance(maxAllowedRadius).map(
                                (msg) => Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "- ",
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: cs.onSurface
                                              .withValues(alpha: 0.72),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          msg,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: cs.onSurface
                                                .withValues(alpha: 0.72),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!widget.focusRadius) ...[
                          const SizedBox(height: 14),
                          ProxGlass(
                            radius: 18,
                            blurSigma: 18,
                            fillOpacity: 0.10,
                            borderOpacity: 0.16,
                            padding: const EdgeInsets.all(12),
                            child: SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              value: _businessOnly,
                              onChanged: (v) =>
                                  setState(() => _businessOnly = v),
                              title: const Text("Business-only matches"),
                              subtitle: Text(
                                _businessOnly
                                    ? "Only show business-ready profiles to speed ROI paths."
                                    : "Include all profiles for broader discovery.",
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ProxGlass(
                            radius: 18,
                            blurSigma: 18,
                            fillOpacity: 0.10,
                            borderOpacity: 0.16,
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Keyword match behavior',
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<KeywordMatchMode>(
                                  initialValue: _keywordMode,
                                  decoration: const InputDecoration(
                                    labelText: "Keyword mode",
                                    isDense: true,
                                  ),
                                  items: _keywordModeItems(),
                                  onChanged: (next) {
                                    if (next == null) return;
                                    setState(() => _keywordMode = next);
                                  },
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  switch (_keywordMode) {
                                    KeywordMatchMode.strict =>
                                      'Strict mode only keeps profiles with direct keyword overlap.',
                                    KeywordMatchMode.singleKeyword =>
                                      'Single Keyword mode keeps profiles with at least one shared active keyword.',
                                    KeywordMatchMode.reciprocalOpposite =>
                                      'Reciprocal Opposite requires BOTH directions to match: your Looking For <-> their Can Provide, and your Can Provide <-> their Looking For.',
                                    KeywordMatchMode.keywordChain =>
                                      'Keyword Chain requires a chain of 2+ shared active keywords.',
                                    KeywordMatchMode.similar =>
                                      'Similar mode keeps broader discovery and ranks by relevance.',
                                  },
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.78),
                                  ),
                                ),
                                if (!_isKeywordModeUnlocked(_keywordMode)) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: cs.secondaryContainer
                                          .withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: cs.secondary
                                              .withValues(alpha: 0.45)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "This keyword mode requires a Prox Store unlock.",
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: cs.onSecondaryContainer,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: FilledButton.icon(
                                            onPressed: () =>
                                                Navigator.of(context)
                                                    .pushNamed("/store"),
                                            icon: const Icon(
                                                Icons.storefront_outlined),
                                            label: const Text("Open Store"),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          GridView.count(
                            shrinkWrap: true,
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.2,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              ProxGlassCard(
                                onTap: () => _setKind(MatchingModeKind.off),
                                highlight: red,
                                glow: red,
                                padding: const EdgeInsets.all(14),
                                child: _ModeCardInner(
                                  icon: Icons.pause_circle_outline,
                                  title: "Matches Off",
                                  subtitle: "No auto-match creation",
                                  selected: _kind == MatchingModeKind.off,
                                  accent: red,
                                ),
                              ),
                              ProxGlassCard(
                                onTap: () => _setKind(MatchingModeKind.normal),
                                highlight: blue,
                                glow: blue,
                                padding: const EdgeInsets.all(14),
                                child: _ModeCardInner(
                                  icon: Icons.radar,
                                  title: "Normal",
                                  subtitle: "Passive or Active",
                                  selected: _kind == MatchingModeKind.normal,
                                  accent: blue,
                                ),
                              ),
                              ProxGlassCard(
                                onTap: () => _setKind(MatchingModeKind.listen),
                                highlight: aqua,
                                glow: aqua,
                                padding: const EdgeInsets.all(14),
                                child: _ModeCardInner(
                                  icon: Icons.hearing,
                                  title: "Listen Mode",
                                  subtitle: "Speak or Listen role matching",
                                  selected: _kind == MatchingModeKind.listen,
                                  accent: aqua,
                                ),
                              ),
                              ProxGlassCard(
                                onTap: () =>
                                    _setKind(MatchingModeKind.treasureHunt),
                                highlight: green,
                                glow: green,
                                padding: const EdgeInsets.all(14),
                                child: _ModeCardInner(
                                  icon: Icons.explore,
                                  title: "Treasure Hunt",
                                  subtitle: "Keyword overlap compass",
                                  selected:
                                      _kind == MatchingModeKind.treasureHunt,
                                  accent: green,
                                ),
                              ),
                              ProxGlassCard(
                                onTap: () => _setKind(MatchingModeKind.travel),
                                highlight: orange,
                                glow: orange,
                                padding: const EdgeInsets.all(14),
                                child: _ModeCardInner(
                                  icon: Icons.directions,
                                  title: "Travel",
                                  subtitle: "Recent movers only (last ~30 min)",
                                  selected: _kind == MatchingModeKind.travel,
                                  accent: orange,
                                ),
                              ),
                            ],
                          ),
                          if (_kind == MatchingModeKind.listen) ...[
                            const SizedBox(height: 14),
                            ProxGlass(
                              radius: 18,
                              blurSigma: 18,
                              fillOpacity: 0.10,
                              borderOpacity: 0.16,
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Listen mode role",
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 8),
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
                                    selected: <ListenMatchRole>{_listenRole},
                                    onSelectionChanged: (next) {
                                      if (next.isNotEmpty)
                                        _setListenRole(next.first);
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _listenRole == ListenMatchRole.speak
                                        ? "Speak role finds nearby users in Listen role."
                                        : "Listen role finds nearby users in Speak role.",
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          cs.onSurface.withValues(alpha: 0.78),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 26),
                          if (_kind == MatchingModeKind.normal)
                            ProxGlass(
                              radius: 18,
                              blurSigma: 18,
                              fillOpacity: 0.10,
                              borderOpacity: 0.16,
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Normal mode behavior",
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 8),
                                  SegmentedButton<NormalMatchMode>(
                                    segments: const [
                                      ButtonSegment(
                                          value: NormalMatchMode.passive,
                                          label: Text("Passive")),
                                      ButtonSegment(
                                          value: NormalMatchMode.active,
                                          label: Text("Active")),
                                    ],
                                    selected: <NormalMatchMode>{_normalMode},
                                    onSelectionChanged: _activeLocked
                                        ? null
                                        : (next) {
                                            if (next.isNotEmpty)
                                              _setNormalMode(next.first);
                                          },
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _activeLocked
                                        ? "Active is temporarily locked for missed responses."
                                        : "Active requires replying to new matches within 10 minutes.",
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          cs.onSurface.withValues(alpha: 0.78),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (_kind == MatchingModeKind.treasureHunt)
                            ProxGlass(
                              radius: 18,
                              blurSigma: 18,
                              fillOpacity: 0.10,
                              borderOpacity: 0.16,
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Treasure radius: ${_treasureRadius.toStringAsFixed(1)} mi",
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  Slider(
                                    value: _treasureRadius,
                                    min: MatchDiscoverySettings.minRadiusMiles,
                                    max: MatchDiscoverySettings.maxRadiusMiles,
                                    divisions: 19,
                                    onChanged: (v) =>
                                        setState(() => _treasureRadius = v),
                                  ),
                                ],
                              ),
                            ),
                          if (_kind == MatchingModeKind.travel)
                            ProxGlass(
                              radius: 18,
                              blurSigma: 18,
                              fillOpacity: 0.10,
                              borderOpacity: 0.16,
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                "Travel mode is strict: it only shows profiles with very recent movement signals. If Nearby looks empty, switch to Normal.",
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.78),
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ProxGlassButton(
                  label: "Continue",
                  onTap: _commitAndClose,
                  highlight: _kind == MatchingModeKind.travel
                      ? orange
                      : (_kind == MatchingModeKind.treasureHunt
                          ? green
                          : (_kind == MatchingModeKind.listen ? aqua : blue)),
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCardInner extends StatelessWidget {
  const _ModeCardInner({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 44,
          color: selected ? accent : cs.onSurface.withValues(alpha: 0.65),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.05,
            color: cs.onSurface.withValues(alpha: 0.92),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.70),
            height: 1.2,
          ),
        ),
      ],
    );
  }
}
