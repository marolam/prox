import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "package:prox/bootstrap/nearby_bootstrap.dart";
import "package:prox/screens/chat/chat_thread_screen.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/chat_service.dart";
import "package:prox/services/device_storage_service.dart";
import "package:prox/services/match_events_service.dart";
import "package:prox/services/now_feed_cleanup_service.dart";
import "package:prox/services/party_mode_service.dart";
import "package:prox/services/party_service.dart";
import "package:prox/services/stream_cache.dart";
import "package:prox/services/user_profile_service.dart";
import "package:prox/utils/presentation/prox_distance_format.dart";
import "package:prox/utils/presentation/prox_identity_policy.dart";
import "package:prox/widgets/prox_background.dart";
import "package:prox/widgets/location_issue_banner.dart";

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  static const String _kRecentKey = "matches.recentNearby";

  List<MatchEvent> _events = const <MatchEvent>[];
  List<Map<String, dynamic>> _recent = const <Map<String, dynamic>>[];
  bool _opening = false;

  late final StreamCache<List<_FsMatchRow>> _fsMatchesCache;
  late final StreamCache<List<_MatchHistoryRow>> _historyCache;

  @override
  void initState() {
    super.initState();

    _fsMatchesCache = StreamCache<List<_FsMatchRow>>(_watchFirestoreMatches);
    _historyCache = StreamCache<List<_MatchHistoryRow>>(_watchMatchHistory);

    DeviceStorageService.instance.load();
    MatchEventsService.instance.ensureLoaded();
    _reload();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 600), () async {
        if (!mounted) return;
        final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
        if (uid.trim().isEmpty) return;
        try {
          await NowFeedCleanupService.instance.pruneAutoIfDue(uid);
        } catch (_) {}
      });
    });
  }

  void _reload() {
    _events = MatchEventsService.instance.readEvents();

    final Map<String, dynamic>? raw = DeviceStorageService.instance.getMap(_kRecentKey);
    final List<dynamic> list = raw?["list"] as List<dynamic>? ?? const <dynamic>[];

    final out = <Map<String, dynamic>>[];
    for (final e in list) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
    }
    setState(() => _recent = out);
  }

  Future<void> _clearAll() async {
    MatchEventsService.instance.clear();
    DeviceStorageService.instance.set(_kRecentKey, <String, Object?>{"list": <Object?>[]});
    _reload();
  }

  Future<void> _openChat(String otherUid) async {
    if (_opening) return;
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    setState(() => _opening = true);
    try {
      final String chatId = await ChatService.instance.ensureDirectChat(otherUid);
      if (!mounted) return;
      final previous = ContextHelpService.instance.contextKey.value;
      ContextHelpService.instance.setContext("matches:chat_thread");
      Navigator.of(context)
          .push(
        MaterialPageRoute<void>(
          builder: (_) => ChatThreadScreen(chatId: chatId, otherUid: otherUid),
        ),
      )
          .then((_) {
        ContextHelpService.instance.setContext(previous);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open chat right now.")),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Stream<List<_FsMatchRow>> _watchFirestoreMatches(String myUid) {
    return FirebaseFirestore.instance
        .collection("matches")
        .where("participants", arrayContains: myUid)
        .snapshots()
        .map((qs) {
      final rows = <_FsMatchRow>[];
      for (final d in qs.docs) {
        final data = d.data();
        final partsDyn = (data["participants"] as List<dynamic>?) ?? const <dynamic>[];
        final parts = partsDyn.map((e) => e.toString()).toList();

        String otherUid = "";
        for (final p in parts) {
          if (p != myUid) {
            otherUid = p;
            break;
          }
        }
        if (otherUid.trim().isEmpty && d.id.contains("__")) {
          final split = d.id.split("__");
          if (split.length == 2) otherUid = (split[0] == myUid) ? split[1] : split[0];
        }
        if (otherUid.trim().isEmpty) continue;

        DateTime? updatedAt;
        final u = data["updatedAt"];
        if (u is Timestamp) updatedAt = u.toDate();
        final c = data["createdAt"];
        if (updatedAt == null && c is Timestamp) updatedAt = c.toDate();

        rows.add(_FsMatchRow(matchId: d.id, otherUid: otherUid, updatedAt: updatedAt));
      }

      rows.sort((a, b) {
        final ad = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });

      return rows;
    });
  }

  Stream<List<_MatchHistoryRow>> _watchMatchHistory(String myUid) {
    return FirebaseFirestore.instance
        .collection("users")
        .doc(myUid)
        .collection("meta")
        .doc("matching")
        .collection("events")
        .orderBy("createdAtClientMs", descending: true)
        .limit(30)
        .snapshots()
        .map((qs) {
      final out = <_MatchHistoryRow>[];
      for (final d in qs.docs) {
        final data = d.data();
        final String otherUid = (data["otherUid"] as String? ?? "").trim();
        if (otherUid.isEmpty) continue;

        final String mode = (data["mode"] as String? ?? "normal").trim();
        final double? distanceMiles = (data["distanceMiles"] as num?)?.toDouble();
        final List<String> sharedKeywords = ((data["sharedKeywords"] as List<dynamic>?) ?? const <dynamic>[])
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .take(3)
            .toList(growable: false);
        final int tsMs = (data["createdAtClientMs"] as num?)?.toInt() ?? 0;

        out.add(
          _MatchHistoryRow(
            eventId: d.id,
            otherUid: otherUid,
            mode: mode,
            distanceMiles: distanceMiles,
            sharedKeywords: sharedKeywords,
            createdAtClientMs: tsMs,
          ),
        );
      }
      return out;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Matches")),
        body: const Center(child: Text("Sign in to see matches.")),
      );
    }
    final events = _events;
    final recents = _recent;

    return StreamBuilder<String?>(
      stream: PartyModeService.instance.watchCurrentPartyId(),
      builder: (context, partyScopeSnap) {
        final isPartyScope = (partyScopeSnap.data ?? "").isNotEmpty;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text("Matches"),
          ),
          body: StreamBuilder<List<PartyMemberEntry>>(
            stream: PartyService.instance.watchMyPartyEntries(),
            builder: (context, partySnap) {
              final partyUids = partySnap.data?.map((e) => e.otherUid.trim()).where((e) => e.isNotEmpty).toSet() ??
                <String>{};
              final partyLoaded = partySnap.hasData ||
                partySnap.connectionState == ConnectionState.active ||
                partySnap.connectionState == ConnectionState.done;
              final applyPartyFilter = partyLoaded && partyUids.isNotEmpty;

              return ProxNebulaBackground(
                child: Stack(
                  children: [
                    StreamBuilder<List<_FsMatchRow>>(
                      stream: _fsMatchesCache.get(me.uid),
                      builder: (context, snap) {
                        final fsMatches = snap.data ?? const <_FsMatchRow>[];

                        return StreamBuilder<List<_MatchHistoryRow>>(
                          stream: _historyCache.get(me.uid),
                          builder: (context, historySnap) {
                            final historyRows = historySnap.data ?? const <_MatchHistoryRow>[];
                            final partyFsMatches = applyPartyFilter
                              ? fsMatches.where((m) => partyUids.contains(m.otherUid)).toList(growable: false)
                              : fsMatches;
                            final partyHistoryRows = applyPartyFilter
                              ? historyRows.where((h) => partyUids.contains(h.otherUid)).toList(growable: false)
                              : historyRows;
                            final partyEvents = applyPartyFilter
                              ? events.where((e) => partyUids.contains(e.otherUid)).toList(growable: false)
                              : events;
                            final partyRecents = applyPartyFilter
                              ? recents
                                .where((r) => partyUids.contains((r["uid"] ?? "").toString().trim()))
                                .toList(growable: false)
                              : recents;

                        return ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _reload,
                              icon: const Icon(Icons.refresh),
                              label: const Text("Refresh"),
                            ),
                            OutlinedButton.icon(
                              onPressed: _clearAll,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text("Clear local"),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const _BootstrapReceiptCard(),
                        const SizedBox(height: 10),
                        _InPartyMatchProgressCard(uid: me.uid),
                        const SizedBox(height: 10),
                        ValueListenableBuilder<NearbyBootstrapDebugState>(
                          valueListenable: NearbyBootstrap.debug,
                          builder: (context, s, _) {
                            if (s.centerKnown) return const SizedBox.shrink();
                            final err = s.lastError.trim();
                            if (err.isEmpty) return const SizedBox.shrink();
                            final low = err.toLowerCase();
                            final show = low.contains("permission") ||
                                low.contains("services off") ||
                                low.contains("denied") ||
                                low.contains("blocked") ||
                                low.contains("timeout") ||
                                low.contains("no /users/") ||
                                low.contains("missing geopoint");
                            if (!show) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: LocationIssueBanner(
                                hint: err,
                                onRetry: () async {
                                  // Force a real restart so retry is effective even if bootstrap is already started.
                                  await proxRestartNearby();
                                },
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        if (!partyLoaded)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              "Loading Party members... showing all matches temporarily.",
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ),
                        if (partySnap.hasError)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              "Party members unavailable right now; showing all matches.",
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ),
                        const _SectionCard(
                          title: "Matches (Firestore)",
                          subtitle: "Created automatically when two devices are nearby (bootstrap).",
                        ),
                        const SizedBox(height: 10),
                        if (snap.hasError)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              "Could not load Firestore matches right now.",
                              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                        if (snap.connectionState == ConnectionState.waiting && partyFsMatches.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              "Loading matches...",
                              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                          )
                        else if (partyFsMatches.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              "No Party-linked matches yet.",
                              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                          for (final m in partyFsMatches) ...[
                            _UserRow(
                              uid: m.otherUid,
                              distanceMiles: null,
                              trailing: _timeAgoLabelFromDate(m.updatedAt),
                              onTap: () => _openChat(m.otherUid),
                              isPartyScope: isPartyScope,
                            ),
                            const SizedBox(height: 8),
                          ],
                        const SizedBox(height: 18),
                        const _SectionCard(
                          title: "Match history (mode audit)",
                          subtitle: "Recent match events with mode and shared-keyword context.",
                        ),
                        const SizedBox(height: 10),
                        if (historySnap.hasError)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              "Could not load match history right now.",
                              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          )
                        else
                        if (historySnap.connectionState == ConnectionState.waiting && partyHistoryRows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              "Loading match history...",
                              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          )
                        else if (partyHistoryRows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              "No Party-linked mode-history events yet.",
                              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          )
                        else
                          for (final h in partyHistoryRows) ...[
                            _MatchHistoryTile(
                              row: h,
                              onTap: () => _openChat(h.otherUid),
                              isPartyScope: isPartyScope,
                            ),
                            const SizedBox(height: 8),
                          ],
                        const SizedBox(height: 18),
                        const _SectionCard(
                          title: "Matches (local taps)",
                          subtitle: "Legacy list: people you tapped from Nearby.",
                        ),
                        const SizedBox(height: 10),
                        if (partyEvents.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              "No Party-linked local tap matches yet.",
                              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          )
                        else
                          for (final e in partyEvents) ...[
                            _UserRow(
                              uid: e.otherUid,
                              distanceMiles: e.distanceMiles,
                              trailing: _timeAgoLabel(e.tsMs),
                              onTap: () => _openChat(e.otherUid),
                              isPartyScope: isPartyScope,
                            ),
                            const SizedBox(height: 8),
                          ],
                        const SizedBox(height: 18),
                        const _SectionCard(
                          title: "Recent nearby (local cache)",
                          subtitle: "People you've recently seen nearby (cached locally).",
                        ),
                        const SizedBox(height: 10),
                        if (partyRecents.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              "No Party-linked nearby history yet.",
                              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          )
                        else
                          for (final item in partyRecents) ...[
                            _UserRow(
                              uid: (item["uid"] as String?) ?? "",
                              distanceMiles: (item["distanceMiles"] as num?)?.toDouble(),
                              trailing: "",
                              onTap: () {
                                final uid = (item["uid"] as String?) ?? "";
                                if (uid.isNotEmpty) _openChat(uid);
                              },
                              isPartyScope: isPartyScope,
                            ),
                            const SizedBox(height: 8),
                          ],
                          ],
                        );
                          },
                        );
                      },
                    ),
                if (_opening)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        alignment: Alignment.topCenter,
                        padding: const EdgeInsets.only(top: 12),
                        child: Card(
                          elevation: 0,
                          color: cs.surfaceContainerHighest,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  "Opening chat...",
                                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  static String _timeAgoLabelFromDate(DateTime? dt) {
    if (dt == null) return "";
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return "just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "${diff.inHours}h ago";
    return "${diff.inDays}d ago";
  }

  String _timeAgoLabel(int tsMs) {
    if (tsMs <= 0) return "";
    return _timeAgoLabelFromDate(DateTime.fromMillisecondsSinceEpoch(tsMs));
  }
}

class _FsMatchRow {
  final String matchId;
  final String otherUid;
  final DateTime? updatedAt;

  const _FsMatchRow({
    required this.matchId,
    required this.otherUid,
    required this.updatedAt,
  });
}

class _MatchHistoryRow {
  final String eventId;
  final String otherUid;
  final String mode;
  final double? distanceMiles;
  final List<String> sharedKeywords;
  final int createdAtClientMs;

  const _MatchHistoryRow({
    required this.eventId,
    required this.otherUid,
    required this.mode,
    required this.distanceMiles,
    required this.sharedKeywords,
    required this.createdAtClientMs,
  });
}

class _MatchHistoryTile extends StatelessWidget {
  const _MatchHistoryTile({
    required this.row,
    required this.onTap,
    required this.isPartyScope,
  });

  final _MatchHistoryRow row;
  final VoidCallback onTap;
  final bool isPartyScope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final List<String> details = <String>[
      "mode:${row.mode}",
      if ((row.distanceMiles ?? 0) > 0)
        ProxDistanceFormat.bucketMilesOrNull(row.distanceMiles) ?? "",
      _MatchesScreenState._timeAgoLabelFromDate(
        row.createdAtClientMs <= 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row.createdAtClientMs),
      ),
    ].where((s) => s.trim().isNotEmpty).toList(growable: false);

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.history_edu_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: FutureBuilder<UserProfile?>(
                  future: (() {
                    final cached = UserProfileService.instance.peekCachedProfile(row.otherUid);
                    if (cached != null) return Future<UserProfile?>.value(cached);
                    return UserProfileService.instance.getProfileOnce(row.otherUid);
                  })(),
                  builder: (context, snap) {
                    final p = snap.data ?? UserProfileService.instance.peekCachedProfile(row.otherUid);
                    final title = ProxIdentityPolicy.displayName(
                      uid: row.otherUid,
                      profile: p,
                      isPartyScope: isPartyScope,
                    );

                    final kw = row.sharedKeywords;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (details.isNotEmpty)
                          Text(
                            details.join(" - "),
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        if (kw.isNotEmpty)
                          Text(
                            "keywords: ${kw.join(", ")}",
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    );
                  },
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _BootstrapReceiptCard extends StatelessWidget {
  const _BootstrapReceiptCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ValueListenableBuilder<NearbyBootstrapDebugState>(
      valueListenable: NearbyBootstrap.debug,
      builder: (context, s, _) {
        final hits = s.lastHits;
        final started = s.started ? "yes" : "no";
        final last = s.lastEnsureUid.isEmpty ? "-" : s.lastEnsureUid;
        final at = s.lastEnsureAt == null ? "" : " - ${_MatchesScreenState._timeAgoLabelFromDate(s.lastEnsureAt)}";
        final err = s.lastError.trim();
        final center = s.centerKnown ? s.centerLabel : "unknown";

        return Card(
          elevation: 0,
          color: cs.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Bootstrap receipts", style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text("started: $started - hits: $hits", style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text("center: $center", style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(
                  "cg total: ${s.cgTotal} - current+geo: ${s.currentWithGeo} - in radius: ${s.inRadius}",
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text("last ensured: $last$at", style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                if (err.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text("error: $err", style: theme.textTheme.bodySmall?.copyWith(color: cs.error, fontWeight: FontWeight.w800)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _InPartyMatchProgressCard extends StatelessWidget {
  const _InPartyMatchProgressCard({required this.uid});

  final String uid;

  static String _badgeFor(int total) {
    if (total >= 50) return "Party Legend";
    if (total >= 20) return "Party Pro";
    if (total >= 10) return "Connector";
    if (total >= 3) return "Starter";
    return "Newcomer";
  }

  static int _nextGoal(int total) {
    if (total < 3) return 3;
    if (total < 10) return 10;
    if (total < 20) return 20;
    if (total < 50) return 50;
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.doc("users/$uid/meta/inPartyMatchMetrics").snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final total = (data["totalInPartyMatches"] as num?)?.toInt() ?? 0;
        final badge = _badgeFor(total);
        final nextGoal = _nextGoal(total);
        final toNext = (nextGoal - total).clamp(0, 1000000);

        return Card(
          elevation: 0,
          color: cs.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "In-Party Match Progress",
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  "Total in-party matches: $total",
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  "Badge: $badge",
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (toNext > 0)
                  Text(
                    "$toNext to next milestone ($nextGoal)",
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.uid,
    required this.distanceMiles,
    required this.trailing,
    required this.onTap,
    this.isPartyScope = false,
  });

  final String uid;
  final double? distanceMiles;
  final String trailing;
  final VoidCallback onTap;
  final bool isPartyScope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (uid.trim().isEmpty) return const SizedBox.shrink();

    final distBucket = ProxDistanceFormat.bucketMilesOrNull(distanceMiles);

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              FutureBuilder<UserProfile?>(
                future: (() {
                  final cached = UserProfileService.instance.peekCachedProfile(uid);
                  if (cached != null) return Future<UserProfile?>.value(cached);
                  return UserProfileService.instance.getProfileOnce(uid);
                })(),
                builder: (context, snap) {
                  final p = snap.data ?? UserProfileService.instance.peekCachedProfile(uid);
                  final name = ProxIdentityPolicy.displayName(
                    uid: uid,
                    profile: p,
                    isPartyScope: isPartyScope,
                  );
                  final photoUrl = (p?.photoUrl ?? "").trim();

                  final subParts = <String>[];
                  if (distBucket != null && distBucket.isNotEmpty) subParts.add(distBucket);
                  if (trailing.trim().isNotEmpty) subParts.add(trailing.trim());

                  return Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                        child: photoUrl.isEmpty ? const Icon(Icons.person, size: 18) : null,
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          if (subParts.isNotEmpty)
                            Text(
                              subParts.join(" - "),
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const Spacer(),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

