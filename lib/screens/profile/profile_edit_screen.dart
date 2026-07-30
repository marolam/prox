// ignore_for_file: invalid_null_aware_operator, unnecessary_type_check

import "dart:async";

import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:image_picker/image_picker.dart";

import "package:prox/bootstrap/nearby_bootstrap.dart";
import "package:prox/screens/monetization/business_paywall_screen.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/image_picker_guard.dart";
import "package:prox/services/ime_visibility_service.dart";
import "package:prox/services/keyword_quality_service.dart";
import "package:prox/services/critical_ui_service.dart";
import "package:prox/services/mode_unlock_service.dart";
import "package:prox/services/monetization_service.dart";
import "package:prox/services/presence_writer.dart";
import "package:prox/services/referral_attribution_service.dart";
import "package:prox/services/tutorial/welcome_tutorial_service.dart";
import "package:prox/services/user_profile_service.dart";
import "package:prox/shell/home_root_shell.dart";

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({
    super.key,
    this.fromOnboarding = false,
  });

  final bool fromOnboarding;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  static const MethodChannel _systemHealthChannel = MethodChannel("prox/system_health");
  static const String _bucketSearchingFor = "searchingFor";
  static const String _bucketCanProvide = "canProvide";
  static const String _bucketPrivateSearchingFor = "privateSearchingFor";
  static const String _bucketPrivateCanProvide = "privateCanProvide";
  static const String _bucketVisibleInventory = "visibleInventory";
  static const String _bucketPrivateInventory = "privateInventory";
  static const String _bucketSatisfied = "satisfied";
  static const String _bucketRemoved = "removed";

  static const List<String> _bucketOrder = <String>[
    _bucketSearchingFor,
    _bucketCanProvide,
    _bucketPrivateSearchingFor,
    _bucketPrivateCanProvide,
    _bucketVisibleInventory,
    _bucketPrivateInventory,
    _bucketSatisfied,
    _bucketRemoved,
  ];

  static const List<String> _editableBuckets = <String>[
    _bucketSearchingFor,
    _bucketCanProvide,
  ];

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _headlineController = TextEditingController();
  final TextEditingController _searchingController = TextEditingController();
  final TextEditingController _providingController = TextEditingController();

  List<String> _searchingKeywords = <String>[];
  List<String> _canProvideKeywords = <String>[];
  Map<String, List<_KeywordBucketItem>> _keywordBuckets =
      <String, List<_KeywordBucketItem>>{};
  Map<String, bool> _bucketUnlocked = <String, bool>{};

  bool _loading = true;
  bool _loadTimedOut = false;
  bool _saving = false;
  bool _pickingPhoto = false;
  bool _textEditorOpen = false;
  bool _formDirty = false;
  bool _hydratingForm = false;
  Timer? _loadWatchdog;

  bool _businessEnabled = false;
  int _availabilityMinutes = 0;

  bool _canUseBusinessTier = false;
  bool _businessPaidUnlock = false;
  ModeUnlockState? _unlockState;

  String? _photoUrl;

  // Web-safe: store XFile + bytes (no dart:io anywhere)
  XFile? _localPhotoX;
  Uint8List? _localPhotoBytes;

  static const Map<int, String> _availabilityOptions = <int, String>{
    0: "Immediate (right now)",
    30: "Within 30 minutes",
    60: "Within 1 hour",
    240: "Within 4 hours",
  };

  @override
  void initState() {
    super.initState();
    // Keep profile editing responsive by pausing live presence churn on this screen.
    CriticalUiService.instance.setActive(true);
    PresenceWriter.instance.beginCriticalUiSection(reason: "profile_edit_open");
    // ignore: discarded_futures
    PresenceWriter.instance.stopLive(reason: "profile_edit_open");
    NearbyBootstrap.instance.dispose();
    _nameController.addListener(_onFormFieldChanged);
    _headlineController.addListener(_onFormFieldChanged);
    _searchingController.addListener(_onFormFieldChanged);
    _providingController.addListener(_onFormFieldChanged);
    _startLoadWatchdog();
    _loadProfile();
  }

  void _onFormFieldChanged() {
    if (_hydratingForm) return;
    _formDirty = true;
  }

  void _startLoadWatchdog() {
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      if (_loading) {
        setState(() => _loadTimedOut = true);
      }
    });
  }

  Future<T> _withTimeout<T>(Future<T> future, T fallback) async {
    try {
      return await future.timeout(const Duration(seconds: 8));
    } catch (_) {
      return fallback;
    }
  }

  Future<T> _withTimeoutOrThrow<T>(Future<T> future, String operation) async {
    try {
      return await future.timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw StateError("$operation timed out. Please check your network and try again.");
    }
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final cached = UserProfileService.instance.peekCachedProfile(uid);
      if (cached != null) {
        _applyProfile(cached, overwrite: true);
        if (mounted) {
          setState(() => _loading = false);
        }
      }

      // Entitlements do not block first render of profile fields.
      // ignore: discarded_futures
      _loadBusinessAccessState(uid);

      final profile = await _withTimeout<UserProfile?>(
        UserProfileService.instance.getProfileOnce(uid),
        null,
      );

      if (!mounted) return;

      if (profile != null) {
        _applyProfile(profile, overwrite: !_formDirty);
      }

      if (_loading) {
        setState(() => _loading = false);
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint("[ProfileEdit] load failed: $e\n$st");
      }
    } finally {
      _loadWatchdog?.cancel();
      if (mounted) {
        setState(() {
          _loading = false;
          _loadTimedOut = false;
        });
      }
    }
  }

  Future<void> _loadBusinessAccessState(String uid) async {
    final unlock = await _withTimeout<ModeUnlockState?>(
      ModeUnlockService.instance.loadForUser(uid),
      null,
    );
    final paid = await _withTimeout<bool>(
      MonetizationService.instance.isBusinessUnlocked(uid),
      false,
    );

    if (!mounted) return;

    setState(() {
      _unlockState = unlock;
      _canUseBusinessTier = unlock?.canUseBusiness ?? false;
      _businessPaidUnlock = paid;
      final bool shouldAllowBusinessToggle = _canUseBusinessTier && _businessPaidUnlock;
      if (!shouldAllowBusinessToggle) {
        _businessEnabled = false;
      }
    });
  }

  void _applyProfile(UserProfile profile, {required bool overwrite}) {
    if (!overwrite) return;

    _hydratingForm = true;
    _nameController.text = profile.displayName ?? "";
    _headlineController.text = profile.headline ?? "";
    _searchingController.text = profile.searching ?? "";
    _providingController.text = profile.providing ?? "";
    _photoUrl = profile.photoUrl;

    _initializeKeywordWorkspace(profile);
    _syncPrimaryKeywordsFromBuckets();

    final bool shouldAllowBusinessToggle = _canUseBusinessTier && _businessPaidUnlock;
    _businessEnabled = shouldAllowBusinessToggle ? profile.isBusiness : false;

    final int? mins = profile.availabilityMinutes;
    _availabilityMinutes = _availabilityOptions.keys.contains(mins) ? (mins ?? 0) : 0;
    _hydratingForm = false;
  }

  void _initializeKeywordWorkspace(UserProfile profile) {
    final Map<String, List<_KeywordBucketItem>> buckets =
        <String, List<_KeywordBucketItem>>{};
    for (final key in _bucketOrder) {
      buckets[key] = <_KeywordBucketItem>[];
    }

    final rawWorkspace = profile.keywordWorkspace;
    if (rawWorkspace != null && rawWorkspace.isNotEmpty) {
      for (final key in _bucketOrder) {
        final rawList = rawWorkspace[key];
        if (rawList is! List) continue;

        final parsed = <_KeywordBucketItem>[];
        for (final raw in rawList) {
          if (raw is Map) {
            final value = (raw["value"] ?? raw["keyword"] ?? "").toString().trim();
            if (value.isEmpty) continue;
            final status = _keywordStatusFromName((raw["status"] ?? "clear").toString());
            parsed.add(_KeywordBucketItem(value: value, status: status));
          } else {
            final value = raw.toString().trim();
            if (value.isEmpty) continue;
            parsed.add(_KeywordBucketItem(value: value, status: _KeywordStatus.clear));
          }
        }
        buckets[key] = _dedupeKeywordItems(parsed);
      }

      final mergedPrivate = <_KeywordBucketItem>[
        ...(buckets[_bucketPrivateSearchingFor] ?? const <_KeywordBucketItem>[]),
        ...(buckets[_bucketPrivateCanProvide] ?? const <_KeywordBucketItem>[]),
        ...(buckets[_bucketPrivateInventory] ?? const <_KeywordBucketItem>[]),
      ];
      buckets[_bucketPrivateCanProvide] = _dedupeKeywordItems(mergedPrivate);
      buckets[_bucketPrivateSearchingFor] = <_KeywordBucketItem>[];
      buckets[_bucketPrivateInventory] = <_KeywordBucketItem>[];
    } else {
      buckets[_bucketSearchingFor] = _normalizeKeywords(profile.searchingFor)
          .map((v) => _KeywordBucketItem(value: v, status: _KeywordStatus.clear))
          .toList(growable: false);
      buckets[_bucketCanProvide] = _normalizeKeywords(profile.canProvide)
          .map((v) => _KeywordBucketItem(value: v, status: _KeywordStatus.clear))
          .toList(growable: false);
        buckets[_bucketPrivateCanProvide] = <_KeywordBucketItem>[];
    }

    _keywordBuckets = buckets;

    final locks = <String, bool>{};
    final rawLocks = profile.keywordSectionLocks ?? const <String, bool>{};
    for (final key in _bucketOrder) {
      locks[key] = rawLocks[key] == true || _editableBuckets.contains(key);
    }
    _bucketUnlocked = locks;
  }

  void _continueWithoutWaiting() {
    _loadWatchdog?.cancel();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadTimedOut = false;
    });
  }

  void _retryLoad() {
    _startLoadWatchdog();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadTimedOut = false;
    });
    // ignore: discarded_futures
    _loadProfile();
  }

  List<String> _normalizeKeywords(Iterable<String> values) {
    final Map<String, String> byKey = <String, String>{};
    for (final raw in values) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      byKey[value.toLowerCase()] = value;
    }
    return byKey.values.toList(growable: false);
  }

  String _normalizeSingleKeyword(String raw) {
    return raw.trim().replaceAll(RegExp(r"\s+"), " ");
  }

  ({int invalid, int duplicates, List<String> samples}) _workspaceQualitySnapshot() {
    final all = <String>[];
    for (final key in _bucketOrder) {
      for (final item in _keywordBuckets[key] ?? const <_KeywordBucketItem>[]) {
        all.add(item.value);
      }
    }

    final seen = <String>{};
    final samples = <String>[];
    int invalid = 0;
    int duplicates = 0;

    for (final raw in all) {
      final result = KeywordQualityService.validate(raw);
      if (!result.isValid) {
        invalid += 1;
        if (result.normalized.isNotEmpty && samples.length < 4) {
          samples.add(result.normalized);
        }
        continue;
      }

      if (!seen.add(result.normalized)) {
        duplicates += 1;
      }
    }

    return (invalid: invalid, duplicates: duplicates, samples: samples);
  }

  Future<bool> _confirmKeywordWarningsBeforeSave({
    required int invalid,
    required int duplicates,
    required List<String> samples,
  }) async {
    if (invalid == 0 && duplicates == 0) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Keyword cleanup warning"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("$invalid invalid and $duplicates duplicate keywords will be removed."),
            if (samples.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text("Examples: ${samples.join(", ")}"),
            ],
            const SizedBox(height: 10),
            const Text("Repeated invalid keywords may lower trust score during periodic quality sweeps."),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Review first"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Continue save"),
          ),
        ],
      ),
    );

    return result == true;
  }

  void _sanitizeKeywordWorkspaceForSave() {
    final seenGlobal = <String>{};

    for (final key in _bucketOrder) {
      final items = _keywordBuckets[key] ?? const <_KeywordBucketItem>[];
      final next = <_KeywordBucketItem>[];
      for (final item in items) {
        final result = KeywordQualityService.validate(item.value);
        if (!result.isValid) continue;
        if (!seenGlobal.add(result.normalized)) continue;
        next.add(item.copyWith(value: result.normalized));
      }
      _keywordBuckets[key] = next;
    }
  }

  String _bucketTitle(String bucketKey) {
    switch (bucketKey) {
      case _bucketSearchingFor:
        return "Looking For";
      case _bucketCanProvide:
        return "Can Provide";
      case _bucketPrivateCanProvide:
        return "Private Workspace";
      case _bucketVisibleInventory:
        return "Visible Inventory";
      case _bucketSatisfied:
        return "Satisfied";
      case _bucketRemoved:
        return "Removed";
      default:
        return bucketKey;
    }
  }

  bool _bucketAffectsMatching(String bucketKey) {
    return bucketKey == _bucketSearchingFor || bucketKey == _bucketCanProvide;
  }

  bool _bucketIsArchiveOnly(String bucketKey) {
    return bucketKey == _bucketSatisfied || bucketKey == _bucketRemoved;
  }

  Color _activeGlowColor(ColorScheme cs, String bucketKey) {
    if (bucketKey == _bucketSearchingFor) return cs.primary;
    if (bucketKey == _bucketCanProvide) return cs.secondary;
    return cs.primary;
  }

  bool _bucketIsEditable(String bucketKey) => _editableBuckets.contains(bucketKey);

  _KeywordStatus _keywordStatusFromName(String raw) {
    switch (raw.trim().toLowerCase()) {
      case "working":
        return _KeywordStatus.working;
      case "satisfied":
        return _KeywordStatus.satisfied;
      case "removed":
        return _KeywordStatus.removed;
      default:
        return _KeywordStatus.clear;
    }
  }

  List<_KeywordBucketItem> _dedupeKeywordItems(List<_KeywordBucketItem> items) {
    final byKey = <String, _KeywordBucketItem>{};
    for (final item in items) {
      final value = _normalizeSingleKeyword(item.value);
      if (value.isEmpty) continue;
      byKey[value.toLowerCase()] = item.copyWith(value: value);
    }
    return byKey.values.toList(growable: false);
  }

  void _syncPrimaryKeywordsFromBuckets() {
    final searching = (_keywordBuckets[_bucketSearchingFor] ?? const <_KeywordBucketItem>[])
      .where((i) => i.status == _KeywordStatus.working)
        .map((i) => i.value)
        .toList(growable: false);
    final provide = (_keywordBuckets[_bucketCanProvide] ?? const <_KeywordBucketItem>[])
      .where((i) => i.status == _KeywordStatus.working)
        .map((i) => i.value)
        .toList(growable: false);

    _searchingKeywords = _normalizeKeywords(searching);
    _canProvideKeywords = _normalizeKeywords(provide);
  }

  Future<void> _promptKeywordAndAddToBucket(String bucketKey) async {
    final value = await _openTextEditorSheet(
      title: "Add keyword to ${_bucketTitle(bucketKey)}",
      initialValue: "",
      minLines: 1,
      maxLines: 1,
    );
    if (!mounted || value == null) return;

    final normalized = _normalizeSingleKeyword(value);
    if (normalized.isEmpty) return;

    final validation = KeywordQualityService.validate(normalized);
    if (!validation.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Use real words only (letters, apostrophe, hyphen).")),
      );
      return;
    }

    final items = <_KeywordBucketItem>[...(_keywordBuckets[bucketKey] ?? const <_KeywordBucketItem>[])];
    final canonical = validation.normalized;
    final exists = items.any((i) => i.value.toLowerCase() == canonical);
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("That keyword is already in this section.")),
      );
      return;
    }

    setState(() {
      _formDirty = true;
      items.add(_KeywordBucketItem(value: canonical, status: _KeywordStatus.clear));
      _keywordBuckets[bucketKey] = _dedupeKeywordItems(items);
      _syncPrimaryKeywordsFromBuckets();
    });
  }

  void _archiveTerminalItems(String bucketKey) {
    final source = <_KeywordBucketItem>[...(_keywordBuckets[bucketKey] ?? const <_KeywordBucketItem>[])];
    if (source.isEmpty) return;

    final keep = <_KeywordBucketItem>[];
    final toSatisfied = <_KeywordBucketItem>[...(_keywordBuckets[_bucketSatisfied] ?? const <_KeywordBucketItem>[])];
    final toRemoved = <_KeywordBucketItem>[...(_keywordBuckets[_bucketRemoved] ?? const <_KeywordBucketItem>[])];

    for (final item in source) {
      if (item.status == _KeywordStatus.satisfied) {
        toSatisfied.add(item);
      } else if (item.status == _KeywordStatus.removed) {
        toRemoved.add(item);
      } else {
        keep.add(item);
      }
    }

    _keywordBuckets[bucketKey] = _dedupeKeywordItems(keep);
    _keywordBuckets[_bucketSatisfied] = _dedupeKeywordItems(toSatisfied);
    _keywordBuckets[_bucketRemoved] = _dedupeKeywordItems(toRemoved);
  }

  void _cycleItemStatus(String bucketKey, int index) {
    if (!_bucketIsEditable(bucketKey) || _bucketIsArchiveOnly(bucketKey)) return;
    final list = <_KeywordBucketItem>[...(_keywordBuckets[bucketKey] ?? const <_KeywordBucketItem>[])];
    if (index < 0 || index >= list.length) return;

    final current = list[index];
    final next = current.status == _KeywordStatus.working
        ? _KeywordStatus.clear
        : _KeywordStatus.working;

    setState(() {
      _formDirty = true;
      list[index] = current.copyWith(status: next);
      _keywordBuckets[bucketKey] = list;
      _syncPrimaryKeywordsFromBuckets();
    });
  }

  Map<String, dynamic> _serializeKeywordWorkspace() {
    final out = <String, dynamic>{};
    for (final key in _bucketOrder) {
      final items = _keywordBuckets[key] ?? const <_KeywordBucketItem>[];
      out[key] = items
          .map(
            (i) => <String, String>{
              "value": i.value,
              "status": i.status.name,
            },
          )
          .toList(growable: false);
    }
    return out;
  }

  Map<String, bool> _serializeBucketLocks() {
    final out = <String, bool>{};
    for (final key in _bucketOrder) {
      out[key] = _bucketUnlocked[key] == true;
    }
    return out;
  }

  void _finalizeUnlockedBucketsBeforeSave() {
    for (final key in _bucketOrder) {
      if (_bucketUnlocked[key] == true) {
        _archiveTerminalItems(key);
        _bucketUnlocked[key] = false;
      }
    }
    _syncPrimaryKeywordsFromBuckets();
  }

  Color _statusFill(ColorScheme cs, _KeywordStatus status) {
    switch (status) {
      case _KeywordStatus.clear:
        return cs.surface.withValues(alpha: 0.18);
      case _KeywordStatus.working:
        return cs.surface.withValues(alpha: 0.18);
      case _KeywordStatus.satisfied:
        return const Color(0xFFA5D6A7);
      case _KeywordStatus.removed:
        return const Color(0xFFEF9A9A);
    }
  }

  Future<String?> _openTextEditorSheet({
    required String title,
    required String initialValue,
    required int minLines,
    required int maxLines,
  }) async {
    if (_textEditorOpen) return null;
    _textEditorOpen = true;

    try {
      final native = await _systemHealthChannel.invokeMethod<String>(
        "promptNativeTextInput",
        <String, Object?>{
          "title": title,
          "initialValue": initialValue,
          "minLines": minLines,
          "maxLines": maxLines,
        },
      );
      if (native != null) return native;
      return null;
    } catch (_) {
      // Fall back to Flutter sheet when native prompt is unavailable.
      return showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (ctx) => _ProfileTextEditorSheet(
          title: title,
          initialValue: initialValue,
          minLines: minLines,
          maxLines: maxLines,
          systemHealthChannel: _systemHealthChannel,
        ),
      );
    } finally {
      _textEditorOpen = false;
    }
  }

  List<_KeywordBucketItem> _recentKeywordItems(String bucketKey, {int count = 5}) {
    final all = _keywordBuckets[bucketKey] ?? const <_KeywordBucketItem>[];
    if (all.length <= count) {
      return List<_KeywordBucketItem>.from(all.reversed);
    }
    return all.reversed.take(count).toList(growable: false);
  }

  Widget _keywordWorkspacePreview(String bucketKey) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final compact = MediaQuery.of(context).size.width < 380;
    final recent = _recentKeywordItems(bucketKey, count: 5);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _bucketTitle(bucketKey),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: "Add keyword",
                onPressed: _saving ? null : () => _promptKeywordAndAddToBucket(bucketKey),
                icon: const Icon(Icons.add_circle_outline),
              ),
              TextButton(
                onPressed: _saving ? null : () => _openKeywordListSheet(bucketKey),
                child: const Text("View all"),
              ),
            ],
          ),
          Text(
            "Tap to activate keyword for matching.",
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          SizedBox(height: compact ? 6 : 8),
          if (recent.isEmpty)
            Text(
              "No keywords yet. Tap + to add.",
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            )
          else
            Wrap(
              spacing: compact ? 6 : 8,
              runSpacing: compact ? 6 : 8,
              children: [
                for (final item in recent)
                  _keywordBubbleChip(
                    bucketKey: bucketKey,
                    index: (_keywordBuckets[bucketKey] ?? const <_KeywordBucketItem>[])
                        .lastIndexWhere((i) => i.value == item.value),
                    item: item,
                    enabled: true,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _keywordBubbleChip({
    required String bucketKey,
    required int index,
    required _KeywordBucketItem item,
    required bool enabled,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final compact = MediaQuery.of(context).size.width < 380;
    final isActiveGlow =
        _bucketAffectsMatching(bucketKey) && item.status == _KeywordStatus.working;
    final glowColor = _activeGlowColor(cs, bucketKey);

    return InkWell(
      onTap: enabled ? () => _cycleItemStatus(bucketKey, index) : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 6 : 7,
        ),
        decoration: BoxDecoration(
          color: _statusFill(cs, item.status),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isActiveGlow
                ? glowColor
                : (enabled ? cs.primary.withValues(alpha: 0.55) : cs.outline.withValues(alpha: 0.40)),
            width: isActiveGlow ? 1.8 : 1.0,
          ),
          boxShadow: isActiveGlow
              ? <BoxShadow>[
                  BoxShadow(
                    color: glowColor.withValues(alpha: 0.30),
                    blurRadius: 6,
                    spreadRadius: 0.4,
                  ),
                ]
              : null,
        ),
        child: Text(
          item.value,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _keywordMetricsMap() {
    final activeSearching = (_keywordBuckets[_bucketSearchingFor] ?? const <_KeywordBucketItem>[])
        .where((i) => i.status == _KeywordStatus.working)
        .length;
    final activeProvide = (_keywordBuckets[_bucketCanProvide] ?? const <_KeywordBucketItem>[])
        .where((i) => i.status == _KeywordStatus.working)
        .length;
    final activeTotal = activeSearching + activeProvide;
    final satisfiedCount = (_keywordBuckets[_bucketSatisfied] ?? const <_KeywordBucketItem>[]).length;
    final removedCount = 0;

    return <String, dynamic>{
      "activeSearchingCount": activeSearching,
      "activeProvideCount": activeProvide,
      "activeTotalCount": activeTotal,
      "satisfiedArchiveCount": satisfiedCount,
      "removedArchiveCount": removedCount,
      "archiveTotalCount": satisfiedCount + removedCount,
      "updatedAtMs": DateTime.now().millisecondsSinceEpoch,
    };
  }

  Future<void> _openKeywordListSheet(String bucketKey) async {
    final selected = <int>{};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final bottomSafeInset = MediaQuery.of(ctx).viewPadding.bottom;
        final sheetBottomPadding = bottomSafeInset > 0 ? bottomSafeInset + 12 : 16.0;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final all = _keywordBuckets[bucketKey] ?? const <_KeywordBucketItem>[];
            return FractionallySizedBox(
              heightFactor: 0.86,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, sheetBottomPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _bucketTitle(bucketKey),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Select keywords, then use Found or Remove.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: all.isEmpty
                          ? Center(
                              child: Text(
                                "No keywords yet.",
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            )
                          : ListView.separated(
                              itemCount: all.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (context, i) {
                                final item = all[i];
                                final isSelected = selected.contains(i);
                                return InkWell(
                                  onTap: () {
                                    setSheetState(() {
                                      if (isSelected) {
                                        selected.remove(i);
                                      } else {
                                        selected.add(i);
                                      }
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Theme.of(context).colorScheme.secondaryContainer
                                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected
                                            ? Theme.of(context).colorScheme.secondary
                                            : Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isSelected
                                              ? Icons.check_circle_outline
                                              : Icons.circle_outlined,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(item.value)),
                                        if (item.status == _KeywordStatus.working)
                                          const Icon(Icons.bolt_outlined, size: 16),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: selected.isEmpty
                                ? null
                                : () async {
                                    final confirmed = await _confirmKeywordBulkAction(
                                      selectedCount: selected.length,
                                      markFound: true,
                                    );
                                    if (!confirmed) return;
                                    _applyKeywordBulkAction(
                                      bucketKey: bucketKey,
                                      selectedIndices: selected,
                                      markFound: true,
                                    );
                                    if (!context.mounted) return;
                                    Navigator.of(context).pop();
                                  },
                            icon: const Icon(Icons.check),
                            label: const Text("Found"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: selected.isEmpty
                                ? null
                                : () async {
                                    final confirmed = await _confirmKeywordBulkAction(
                                      selectedCount: selected.length,
                                      markFound: false,
                                    );
                                    if (!confirmed) return;
                                    _applyKeywordBulkAction(
                                      bucketKey: bucketKey,
                                      selectedIndices: selected,
                                      markFound: false,
                                    );
                                    if (!context.mounted) return;
                                    Navigator.of(context).pop();
                                  },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text("Remove"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _confirmKeywordBulkAction({
    required int selectedCount,
    required bool markFound,
  }) async {
    final action = markFound ? "Found" : "Removed";
    final icon = markFound ? "check" : "trash";
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm keyword action"),
        content: Text(
          "Are you sure you want to permanantly mark $selectedCount keywords \"$action\" (with $icon icon)?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Confirm")),
        ],
      ),
    );
    return result == true;
  }

  void _applyKeywordBulkAction({
    required String bucketKey,
    required Set<int> selectedIndices,
    required bool markFound,
  }) {
    final source = <_KeywordBucketItem>[...(_keywordBuckets[bucketKey] ?? const <_KeywordBucketItem>[])];
    if (source.isEmpty || selectedIndices.isEmpty) return;

    final selectedItems = <_KeywordBucketItem>[];
    for (int i = 0; i < source.length; i++) {
      if (selectedIndices.contains(i)) {
        selectedItems.add(source[i]);
      }
    }

    final keep = <_KeywordBucketItem>[];
    for (int i = 0; i < source.length; i++) {
      if (!selectedIndices.contains(i)) {
        keep.add(source[i]);
      }
    }

    final satisfied = <_KeywordBucketItem>[...(_keywordBuckets[_bucketSatisfied] ?? const <_KeywordBucketItem>[])];
    if (markFound) {
      for (final item in selectedItems) {
        satisfied.add(item.copyWith(status: _KeywordStatus.satisfied));
      }
    }

    setState(() {
      _formDirty = true;
      _keywordBuckets[bucketKey] = _dedupeKeywordItems(keep);
      if (markFound) {
        _keywordBuckets[_bucketSatisfied] = _dedupeKeywordItems(satisfied);
      }
      _syncPrimaryKeywordsFromBuckets();
    });
  }

  bool get _hasAnyPhoto {
    return _localPhotoBytes != null || ((_photoUrl ?? "").trim().isNotEmpty);
  }

  Future<bool> _pickPhoto(ImageSource src) async {
    if (_pickingPhoto || ImagePickerGuard.isActive) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Image picker is already open.")),
        );
      }
      return false;
    }

    if (!ImagePickerGuard.tryAcquire()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Image picker is already open.")),
        );
      }
      return false;
    }

    if (mounted) {
      setState(() => _pickingPhoto = true);
    } else {
      _pickingPhoto = true;
    }
    final picker = ImagePicker();
    XFile? img;
    try {
      img = await picker.pickImage(
        source: src,
        maxWidth: 640,
        maxHeight: 640,
        imageQuality: 60,
      );
      if (img == null) {
        final LostDataResponse lost = await picker.retrieveLostData();
        if (!lost.isEmpty && lost.files != null && lost.files!.isNotEmpty) {
          img = lost.files!.first;
        }
      }
    } catch (e, st) {
      final String msg = e.toString().toLowerCase();
      if (msg.contains("already_active") || msg.contains("already being used")) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Image picker is already open.")),
          );
        }
        return false;
      }
      if (kDebugMode) {
        debugPrint("[ProfileEdit] image picker failed: $e\n$st");
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't open image picker: $e")),
        );
      }
      return false;
    } finally {
      ImagePickerGuard.release();
      if (mounted) {
        setState(() => _pickingPhoto = false);
      } else {
        _pickingPhoto = false;
      }
    }
    if (img == null) return false;

    Uint8List? bytes;
    try {
      bytes = await img.readAsBytes();
    } catch (_) {
      bytes = null;
    }
    if (bytes == null || bytes.isEmpty) return false;

    setState(() {
      _formDirty = true;
      _localPhotoX = img;
      _localPhotoBytes = bytes;
    });

    return true;
  }

  Future<bool> _ensureTutorialAction(String actionId) async {
    final tutorial = WelcomeTutorialService.instance;
    if (tutorial.isActionAllowedOnScreen(
      screenId: "profile_edit",
      actionId: actionId,
    )) {
      return true;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Quick tutorial: use the highlighted control to continue.")),
    );
    return false;
  }

  bool _isPermanentUploadFailure(Object error) {
    final s = error.toString().toLowerCase();
    return s.contains("http 403") ||
        s.contains("httpresult: 403") ||
        s.contains("permission denied") ||
        s.contains("does not have permission") ||
        s.contains("http 412") ||
        s.contains("httpresult: 412") ||
        s.contains("missing necessary permissions") ||
        s.contains("re-link");
  }

  Future<String?> _uploadPhotoIfNeeded(String uid) async {
    if (_localPhotoX == null) return _photoUrl;

    Object? lastError;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final url = await UserProfileService.instance
            .uploadProfilePhoto(uid: uid, file: _localPhotoX!)
            .timeout(const Duration(seconds: 30));
        if (url.trim().isNotEmpty) return url;
        lastError = StateError("Upload returned empty URL.");
      } catch (e) {
        lastError = e;
        if (e is TimeoutException) {
          break;
        }
        if (_isPermanentUploadFailure(e)) {
          break;
        }
      }

      if (attempt < 3) {
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }

    throw StateError("Photo upload failed. ${lastError ?? ""}".trim());
  }

  Future<void> _finishToHomeShellRoot() async {
    if (!mounted) return;

    ContextHelpService.instance.setContext("home:hq");

    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const HomeRootShell()),
      (route) => false,
    );
  }

  Future<void> _showBusinessRequirements() async {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final s = _unlockState;
    final needed = s?.neededForBusiness ?? 0;
    final referrals = s?.verifiedReferrals ?? 0;
    final meetups = s?.completedMeetups ?? 0;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_outline, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Business Mode unlock",
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  "Business Mode is earned first (trust + activity), then activated with payment.",
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Progress snapshot", style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text("Verified referrals: $referrals", style: tt.bodyMedium),
                      Text("Completed meetups: $meetups", style: tt.bodyMedium),
                      const SizedBox(height: 8),
                      Text(
                        needed <= 0 ? "You're close - refresh your profile in a moment." : "Steps remaining (combined): $needed",
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text("Got it"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openBusinessPaywall() async {
    final changed = await BusinessPaywallScreen.open(context);
    if (!mounted) return;

    if (changed == true) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final paid = await MonetizationService.instance.isBusinessUnlocked(uid);
      if (!mounted) return;

      setState(() {
        _businessPaidUnlock = paid;
        if (!_businessPaidUnlock) _businessEnabled = false;
      });
    }
  }

  String _friendlySaveError(Object e) {
    if (e is StateError) {
      final msg = e.message?.toString().trim() ?? "";
      if (msg.isNotEmpty) return msg;
      return "Save failed (state error).";
    }

    final s = e.toString().trim();
    if (s.isNotEmpty && s != "Exception") return s;

    return "Unknown error while saving profile.";
  }

  String _debugSaveError(Object e, StackTrace st) {
    final b = StringBuffer();
    b.writeln("PROX PROFILE SAVE ERROR");
    b.writeln("time=${DateTime.now().toIso8601String()}");
    b.writeln("type=${e.runtimeType}");
    if (e is StateError) {
      b.writeln("stateErrorMessage=${e.message}");
    }
    b.writeln("toString=${e.toString()}");
    b.writeln("");
    b.writeln("STACK:");
    b.writeln(st.toString());
    return b.toString();
  }

  Future<void> _copyErrorToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {}
  }

  Future<void> _openUploadDebugScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const _ProfileUploadDebugScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _editFieldInDialog({
    required String title,
    required TextEditingController controller,
    int minLines = 1,
    int maxLines = 1,
  }) async {
    final String? value = await _openTextEditorSheet(
      title: title,
      initialValue: controller.text,
      minLines: minLines,
      maxLines: maxLines,
    );

    if (value != null && mounted) {
      setState(() => controller.text = value);
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    if (!(await _ensureTutorialAction("profile.save_profile"))) return;

    if (!_formKey.currentState!.validate()) return;

    if (!_hasAnyPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please add a selfie before saving.")),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _saving = true);

    try {
      if (_localPhotoX != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Uploading photo...")),
        );
      }

      final String? finalPhotoUrl = await _uploadPhotoIfNeeded(uid);
      if (finalPhotoUrl == null || finalPhotoUrl.trim().isEmpty) {
        throw StateError("Photo upload did not return a valid URL.");
      }

      _finalizeUnlockedBucketsBeforeSave();

      final quality = _workspaceQualitySnapshot();
      final okToContinue = await _confirmKeywordWarningsBeforeSave(
        invalid: quality.invalid,
        duplicates: quality.duplicates,
        samples: quality.samples,
      );
      if (!okToContinue) {
        if (mounted) setState(() => _saving = false);
        return;
      }

      _sanitizeKeywordWorkspaceForSave();
      _syncPrimaryKeywordsFromBuckets();

      if (_searchingKeywords.isEmpty || _canProvideKeywords.isEmpty) {
        throw StateError("Add at least 1 keyword in both Searching For and Can Provide.");
      }

      final List<String> searchingFor = _normalizeKeywords(_searchingKeywords);
      final List<String> canProvide = _normalizeKeywords(_canProvideKeywords);

      final bool allowBusinessToggle = _canUseBusinessTier && _businessPaidUnlock;
      final bool finalBusinessEnabled = allowBusinessToggle ? _businessEnabled : false;

      await _withTimeoutOrThrow<void>(
        UserProfileService.instance.upsertProfile(
          uid: uid,
          displayName: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
          photoUrl: finalPhotoUrl,
          headline: _headlineController.text.trim().isEmpty ? null : _headlineController.text.trim(),
          searchingText: _searchingController.text.trim().isEmpty ? null : _searchingController.text.trim(),
          providingText: _providingController.text.trim().isEmpty ? null : _providingController.text.trim(),
          searchingFor: searchingFor,
          canProvide: canProvide,
          keywordWorkspace: _serializeKeywordWorkspace(),
          keywordSectionLocks: _serializeBucketLocks(),
          keywordMetrics: _keywordMetricsMap(),
          isBusiness: finalBusinessEnabled,
          availabilityMinutes: finalBusinessEnabled ? _availabilityMinutes : null,
        ),
        "Profile save",
      );

      // Best-effort; do not block profile save UX.
      unawaited(
        ReferralAttributionService.instance
            .applyIfPossible(explicitUid: uid)
            .catchError((e) {
          if (kDebugMode) debugPrint("[ProfileEdit] referral apply after save failed: $e");
          return false;
        }),
      );

      if (!mounted) return;

      if (kDebugMode) {
        debugPrint(
          "[ProfileEdit] saved ok. fromOnboarding=${widget.fromOnboarding} "
          "photo=${finalPhotoUrl.trim().isNotEmpty} "
          "searchingFor=${searchingFor.length} canProvide=${canProvide.length} "
          "businessAllowed=$allowBusinessToggle business=$finalBusinessEnabled",
        );
      }

      // Move the tutorial forward only after successful profile save.
      // ignore: discarded_futures
      WelcomeTutorialService.instance.consumeExpectedAction("profile.save_profile");

      if (widget.fromOnboarding) {
        await _finishToHomeShellRoot();
        return;
      }

      Navigator.of(context).pop(true);
    } catch (e, st) {
      if (!mounted) return;

      final Object errObj = e;
      final msg = _friendlySaveError(errObj);
      final dbg = _debugSaveError(errObj, st);

      if (kDebugMode) {
        debugPrint("[ProfileEdit] save failed:\n$dbg");
      }

      await _copyErrorToClipboard(dbg);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't save profile: $msg (details copied)")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _loadWatchdog?.cancel();
    CriticalUiService.instance.setActive(false);
    PresenceWriter.instance.endCriticalUiSection(reason: "profile_edit_close");
    // Resume live presence after leaving profile edit.
    // ignore: discarded_futures
    PresenceWriter.instance.startLive(reason: "profile_edit_close");
    // Resume nearby bootstrap after profile edit is closed.
    // ignore: discarded_futures
    proxBootstrapNearby();
    _nameController.dispose();
    _headlineController.dispose();
    _searchingController.dispose();
    _providingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 14),
                Text(
                  "Loading profile...",
                  style: theme.textTheme.bodyMedium,
                ),
                if (_loadTimedOut) ...[
                  const SizedBox(height: 8),
                  Text(
                    "This is taking longer than expected.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _retryLoad,
                        child: const Text("Retry"),
                      ),
                      FilledButton(
                        onPressed: _continueWithoutWaiting,
                        child: const Text("Continue"),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    ImageProvider? img;
    if (_localPhotoBytes != null && _localPhotoBytes!.isNotEmpty) {
      img = MemoryImage(_localPhotoBytes!);
    } else if ((_photoUrl ?? "").trim().isNotEmpty) {
      img = NetworkImage((_photoUrl ?? "").trim());
    }

    final bool allowBusinessToggle = _canUseBusinessTier && _businessPaidUnlock;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fromOnboarding ? "Create profile" : "Edit profile"),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Save"),
          ),
        ],
      ),
      body: Stack(children: [ if (_saving) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
          SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Center(
                      child: Column(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 44,
                                backgroundImage: img,
                                child: img == null ? const Icon(Icons.person, size: 44) : null,
                              ),
                              if (kDebugMode)
                                Positioned(
                                  right: -6,
                                  top: -6,
                                  child: IconButton.filledTonal(
                                    tooltip: "Upload debug",
                                    onPressed: _openUploadDebugScreen,
                                    icon: const Icon(Icons.bug_report_outlined, size: 18),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.camera_alt),
                                label: const Text("Camera"),
                                onPressed: (_saving || _pickingPhoto)
                                    ? null
                                    : () async {
                                        if (!(await _ensureTutorialAction("profile.add_photo"))) {
                                          return;
                                        }
                                        final didPick = await _pickPhoto(ImageSource.camera);
                                        if (didPick) {
                                          // ignore: discarded_futures
                                          WelcomeTutorialService.instance.consumeExpectedAction("profile.add_photo");
                                        }
                                      },
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.photo),
                                label: const Text("Gallery"),
                                onPressed: (_saving || _pickingPhoto)
                                    ? null
                                    : () async {
                                        if (!(await _ensureTutorialAction("profile.add_photo"))) {
                                          return;
                                        }
                                        final didPick = await _pickPhoto(ImageSource.gallery);
                                        if (didPick) {
                                          // ignore: discarded_futures
                                          WelcomeTutorialService.instance.consumeExpectedAction("profile.add_photo");
                                        }
                                      },
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Selfie is required.",
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameController,
                  readOnly: true,
                  onTap: () => _editFieldInDialog(
                    title: "Edit name",
                    controller: _nameController,
                  ),
                  decoration: InputDecoration(
                    labelText: "Name",
                    suffixIcon: IconButton(
                      tooltip: "Edit in dialog",
                      onPressed: () => _editFieldInDialog(
                        title: "Edit name",
                        controller: _nameController,
                      ),
                      icon: const Icon(Icons.open_in_new),
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? "Please enter a name." : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _headlineController,
                  readOnly: true,
                  onTap: () => _editFieldInDialog(
                    title: "Edit headline",
                    controller: _headlineController,
                  ),
                  decoration: InputDecoration(
                    labelText: "Headline (optional)",
                    hintText: "Short line like \"Web dev in Boca\"",
                    suffixIcon: IconButton(
                      tooltip: "Edit in dialog",
                      onPressed: () => _editFieldInDialog(
                        title: "Edit headline",
                        controller: _headlineController,
                      ),
                      icon: const Icon(Icons.open_in_new),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "Keywords",
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                _keywordWorkspacePreview(_bucketSearchingFor),
                const SizedBox(height: 10),
                _keywordWorkspacePreview(_bucketCanProvide),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Business Mode", style: theme.textTheme.titleMedium),
                ),
                const SizedBox(height: 6),
                Card(
                  elevation: 0,
                  color: cs.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: cs.outline.withValues(alpha: 0.25)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Party  Public  Business",
                          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Business Mode is earned first (trust + activity), then activated with payment. "
                          "Prox must always make the payment path reachable - no dead ends.",
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 10),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: allowBusinessToggle ? _businessEnabled : false,
                          onChanged: (!_canUseBusinessTier || !_businessPaidUnlock || _saving)
                              ? null
                              : (v) => setState(() => _businessEnabled = v),
                          title: const Text("Use Prox in Business Mode"),
                          subtitle: Text(
                            !_canUseBusinessTier
                                ? "Locked: earn unlock first."
                                : (!_businessPaidUnlock
                                    ? "Unlocked to buy: activate with payment."
                                    : "Optional: turn on when you're open for quick meetups/services."),
                          ),
                        ),
                        if (!_canUseBusinessTier) ...[
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _saving ? null : _showBusinessRequirements,
                              icon: const Icon(Icons.lock_outline),
                              label: const Text("See unlock requirements"),
                            ),
                          ),
                        ] else if (!_businessPaidUnlock) ...[
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _saving ? null : _openBusinessPaywall,
                              icon: const Icon(Icons.payments_outlined),
                              label: const Text("Activate Business Mode"),
                            ),
                          ),
                        ],
                        if (allowBusinessToggle && _businessEnabled) ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<int>(
                            initialValue: _availabilityMinutes,
                            decoration: const InputDecoration(labelText: "Typical response time"),
                            items: _availabilityOptions.entries
                                .map((e) => DropdownMenuItem<int>(value: e.key, child: Text(e.value)))
                                .toList(growable: false),
                            onChanged: _saving ? null : (v) => setState(() => _availabilityMinutes = v ?? 0),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                    Text(
                      "These basics unlock matching and chats. You can refine the rest later.",
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Temporarily disabled here while resolving Android IME focus regressions.
          // const WelcomeTutorialBubble(
          //   screenId: "profile_edit",
          //   targetKeys: <String, GlobalKey>{},
          // ),
        ],
      ),
    );
  }
}

class _ProfileUploadDebugScreen extends StatelessWidget {
  const _ProfileUploadDebugScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    String trim(String? s) => (s ?? "").trim();
    String short(String s) {
      if (s.length <= 260) return s;
      return "${s.substring(0, 260)}...";
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Upload debug")),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ValueListenableBuilder<ProfileUploadDebugState>(
            valueListenable: UserProfileService.instance.uploadDebug,
            builder: (context, dbg, _) {
              final status = trim(dbg.status).isEmpty ? "idle" : trim(dbg.status);
              final bucket = trim(dbg.bucket).isEmpty ? "(unknown)" : trim(dbg.bucket);
              final path = trim(dbg.path).isEmpty ? "-" : trim(dbg.path);
              final uid = trim(dbg.uid).isEmpty ? "-" : trim(dbg.uid);
              final error = trim(dbg.error);

              return ListView(
                children: [
                  _debugRow(context, "Status", status),
                  _debugRow(context, "Bucket", bucket),
                  _debugRow(context, "UID", uid),
                  _debugRow(context, "Path", path),
                  if (error.isNotEmpty)
                    _debugRow(
                      context,
                      "Error",
                      short(error),
                      valueStyle: theme.textTheme.bodyMedium?.copyWith(color: cs.error),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _debugRow(
    BuildContext context,
    String label,
    String value, {
    TextStyle? valueStyle,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(value, style: valueStyle ?? theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

enum _KeywordStatus {
  clear,
  working,
  satisfied,
  removed,
}

class _KeywordBucketItem {
  const _KeywordBucketItem({
    required this.value,
    required this.status,
  });

  final String value;
  final _KeywordStatus status;

  _KeywordBucketItem copyWith({
    String? value,
    _KeywordStatus? status,
  }) {
    return _KeywordBucketItem(
      value: value ?? this.value,
      status: status ?? this.status,
    );
  }
}

class _ProfileTextEditorScreen extends StatefulWidget {
  const _ProfileTextEditorScreen({
    required this.title,
    required this.initialValue,
    required this.minLines,
    required this.maxLines,
  });

  final String title;
  final String initialValue;
  final int minLines;
  final int maxLines;

  @override
  State<_ProfileTextEditorScreen> createState() => _ProfileTextEditorScreenState();
}

class _ProfileTextEditorSheet extends StatefulWidget {
  const _ProfileTextEditorSheet({
    required this.title,
    required this.initialValue,
    required this.minLines,
    required this.maxLines,
    required this.systemHealthChannel,
  });

  final String title;
  final String initialValue;
  final int minLines;
  final int maxLines;
  final MethodChannel systemHealthChannel;

  @override
  State<_ProfileTextEditorSheet> createState() => _ProfileTextEditorSheetState();
}

class _ProfileTextEditorSheetState extends State<_ProfileTextEditorSheet> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  void _requestIme() {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    // ignore: discarded_futures
    widget.systemHealthChannel.invokeMethod<bool>("forceShowKeyboard");
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestIme();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(_controller.text),
                child: const Text("Use"),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            textInputAction: TextInputAction.done,
            onTap: _requestIme,
            onSubmitted: (_) => Navigator.of(context).pop(_controller.text),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTextEditorScreenState extends State<_ProfileTextEditorScreen> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  Timer? _imeRetryTimer;
  int _imeRetryCount = 0;

  static const int _maxImeRetries = 18;
  static const Duration _imeRetryEvery = Duration(milliseconds: 120);

  void _requestKeyboard() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 90));
      if (!mounted) return;
      _focusNode.requestFocus();
      await SystemChannels.textInput.invokeMethod<void>("TextInput.show");
      _startImeRetryLoop();
    });
  }

  void _startImeRetryLoop() {
    _imeRetryTimer?.cancel();
    _imeRetryCount = 0;

    _imeRetryTimer = Timer.periodic(_imeRetryEvery, (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (ImeVisibilityService.instance.isVisible) {
        timer.cancel();
        return;
      }

      _imeRetryCount += 1;
      if (_imeRetryCount >= _maxImeRetries) {
        timer.cancel();
        return;
      }

      if (!_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
      await SystemChannels.textInput.invokeMethod<void>("TextInput.show");
    });
  }

  @override
  void initState() {
    super.initState();
    ImeVisibilityService.instance.ensureStarted();
    _controller = TextEditingController(text: widget.initialValue);
    _requestKeyboard();
  }

  @override
  void dispose() {
    _imeRetryTimer?.cancel();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: const Text("Use"),
          ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _requestKeyboard,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextFormField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              textInputAction: TextInputAction.done,
              onTap: _requestKeyboard,
              onFieldSubmitted: (_) => Navigator.of(context).pop(_controller.text),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}







