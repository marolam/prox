import "dart:async";
import "dart:ui";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/screens/discovery/matching_mode_screen.dart";
import "package:prox/services/chat/chat_gate_service.dart";
import "package:prox/services/chat/chat_thread_service.dart";
import "package:prox/services/chat/unread_counter_service.dart";
import "package:prox/services/geoquery_service.dart";
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

class MatchInboxScreen extends StatefulWidget {
  const MatchInboxScreen({super.key});

  @override
  State<MatchInboxScreen> createState() => _MatchInboxScreenState();
}

class _MatchInboxScreenState extends State<MatchInboxScreen> {
  bool _opening = false;
  String _openingUid = "";

  String _topUid = "";
  String _topDistanceLabel = "Nearby";
  List<String> _topKeywords = const <String>[];

  // Ticks UI so decline cooldown chips count down live.
  // Kept intentionally low-frequency to reduce rebuild cost.
  Timer? _uiTick;

  @override
  void initState() {
    super.initState();
    _uiTick = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTick?.cancel();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmtMMSS(Duration d) {
    final s = d.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, "0");
    final ss = (s % 60).toString().padLeft(2, "0");
    return "$mm:$ss";
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
              color: strong
                  ? cs.onSurface
                  : cs.onSurface.withValues(alpha: 0.72),
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

    final byMe = gate.requestedBy.isNotEmpty && gate.requestedBy == myUid;
    return byMe ? _chip("Request sent") : _chip("Chat requested", strong: true);
  }

  Widget _inlineGateActions({
    required String chatId,
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
    if (gate.isAccepted || gate.isDeclined) return const SizedBox.shrink();
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
                final radiusMiles = discovery.radiusMiles;

                return StreamBuilder<String?>(
                  stream: PartyModeService.instance.watchCurrentPartyId(),
                  builder: (context, partyScopeSnap) {
                    final myPartyId = partyScopeSnap.data;

                    return CustomScrollView(
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
                                            color: cs.onSurface.withValues(alpha: 0.85),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Match",
                                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  color: cs.onSurface.withValues(alpha: 0.85),
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
                                            color: cs.onSurface.withValues(alpha: 0.85),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Mode",
                                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color: cs.onSurface.withValues(alpha: 0.85),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                            child: ProxGlass(
                              radius: 22,
                              blurSigma: 18,
                              fillOpacity: 0.10,
                              borderOpacity: 0.16,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Icon(Icons.radar, color: cs.primary),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      discovery.businessOnly
                                          ? "Business discovery enabled"
                                          : "Shared interests nearby",
                                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: cs.onSurface.withValues(alpha: 0.92),
                                          ),
                                    ),
                                  ),
                                  _chip("${radiusMiles.toStringAsFixed(1)} mi", strong: true),
                                ],
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
                                final err = GeoQueryService.instance.debug.lastError.trim();
                                if (err.isEmpty) return const SizedBox.shrink();
                                if (!_isLocationBlockingError(err)) return const SizedBox.shrink();

                                return LocationIssueBanner(
                                  hint: err,
                                  onRetry: () async {
                                    await PresenceWriter.instance.forceWrite(reason: "nearby_retry");
                                    if (!mounted) return;
                                    _snack("Retry requested.");
                                  },
                                );
                              },
                            ),
                          ),
                        ),

                        SliverPadding(
                          padding: EdgeInsets.only(
                            left: 10,
                            right: 10,
                            bottom: 16 + bottomInset,
                          ),
                          sliver: StreamBuilder<List<NearbyDoc>>(
                            stream: GeoQueryService.instance.streamNearby(
                              center: null,
                              radiusMiles: radiusMiles,
                            ),
                            builder: (context, snap) {
                              final rawNearby = snap.data ?? const <NearbyDoc>[];
                              final nearby = _applyBusinessFilter(rawNearby, discovery);

                              return FutureBuilder(
                                future: MatchPipeline.instance.buildCandidates(
                                  nearby: nearby,
                                  myPartyId: myPartyId ?? "",
                                ),
                                builder: (context, rankedSnap) {
                                  if (!rankedSnap.hasData) {
                                    return const SliverToBoxAdapter(
                                      child: Padding(
                                        padding: EdgeInsets.only(top: 44),
                                        child: Center(child: CircularProgressIndicator()),
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

                                    return SliverToBoxAdapter(
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 26),
                                        child: Center(
                                          child: Text(
                                            "No one nearby",
                                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                  color: cs.onSurface.withValues(alpha: 0.72),
                                                ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  WidgetsBinding.instance.addPostFrameCallback((_) => _captureTopCandidate(items));

                                  return SliverList.builder(
                                    itemCount: items.length,
                                    itemBuilder: (context, i) {
                                      final c = items[i];

                                      final String myUid =
                                          FirebaseAuth.instance.currentUser?.uid ?? "";
                                      final String? chatId = myUid.isEmpty
                                          ? null
                                          : ChatThreadService.instance.chatIdFor(myUid, c.uid);

                                      final bool openingThis = _opening && _openingUid == c.uid;

                                      final Stream<DocumentSnapshot<Map<String, dynamic>>> chatDocStream =
                                          (chatId == null)
                                              ? const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty()
                                              : FirebaseFirestore.instance.collection("chats").doc(chatId).snapshots();

                                      final Stream<MeetupRequestState?> meetupStream =
                                          (chatId == null)
                                              ? const Stream<MeetupRequestState?>.empty()
                                              : MeetupService.instance.watchRequestState(chatId: chatId);

                                      NearbyDoc? nd;
                                      for (final d in nearby) {
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
                                          final Duration? declineLeft =
                                              MeetupService.instance.declineCooldownLeftFromState(meetupState);
                                          final bool cooling =
                                              (declineLeft != null && declineLeft > Duration.zero);

                                          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                                            stream: chatDocStream,
                                            builder: (context, chatSnap) {
                                              ChatGateStatus? gate;
                                              if (chatSnap.data != null && chatSnap.data!.exists) {
                                                gate = ChatGateStatus.fromChatDoc(chatSnap.data!.data());
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
                                                  myUid: myUid,
                                                  gate: gate,
                                                  cooling: cooling,
                                                  openingThis: openingThis,
                                                );
                                                if (inline is! SizedBox) {
                                                  right = inline;
                                                } else if (chatDeclined) {
                                                  right = Icon(Icons.block_flipped, color: cs.onSurface.withValues(alpha: 0.75));
                                                } else if (cooling) {
                                                  right = Icon(Icons.lock_clock, color: cs.onSurface.withValues(alpha: 0.75));
                                                } else {
                                                  right = StreamBuilder<int>(
                                                    stream: UnreadCounterService.instance.unreadCount(chatId, myUid),
                                                    builder: (context, s) {
                                                      final n = s.data ?? 0;
                                                      if (n <= 0) {
                                                        return Icon(Icons.chat_bubble_outline, color: cs.onSurface.withValues(alpha: 0.75));
                                                      }
                                                      return CircleAvatar(
                                                        radius: 12,
                                                        backgroundColor: cs.primary.withValues(alpha: 0.22),
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
                                                right = Icon(Icons.chat_bubble_outline, color: cs.onSurface.withValues(alpha: 0.75));
                                              }

                                              return Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
                                                child: ProxGlassCard(
                                                  onTap: onTap,
                                                  highlight: isBiz ? const Color(0xFFFF8A3D) : cs.primary,
                                                  glow: isBiz ? const Color(0xFFFF8A3D) : cs.primary,
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                                  child: Row(
                                                    children: [
                                                      StreamBuilder<UserProfile?>(
                                                        stream: UserProfileService.instance.watchProfile(c.uid),
                                                        builder: (context, ps) {
                                                          final p = ps.data;
                                                          final photoUrl = p?.photoUrl?.trim() ?? "";
                                                          return CircleAvatar(
                                                            radius: 18,
                                                            backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                                                            child: photoUrl.isEmpty ? const Icon(Icons.person, size: 18) : null,
                                                          );
                                                        },
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child: StreamBuilder<UserProfile?>(
                                                          stream: UserProfileService.instance.watchProfile(c.uid),
                                                          builder: (context, ps) {
                                                            final p = ps.data;
                                                            final name = ProxIdentityPolicy.displayName(
                                                              uid: c.uid,
                                                              profile: p,
                                                              isPartyScope: isPartyScope,
                                                            );

                                                            return Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                Row(
                                                                  children: [
                                                                    Expanded(
                                                                      child: Text(
                                                                        name,
                                                                        overflow: TextOverflow.ellipsis,
                                                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                                              fontWeight: FontWeight.w800,
                                                                              color: cs.onSurface.withValues(alpha: 0.92),
                                                                            ),
                                                                      ),
                                                                    ),
                                                                    if (isBiz) ...[
                                                                      const SizedBox(width: 8),
                                                                      _chip(
                                                                        (avail != null && avail <= 0) ? "Business  Now" : "Business",
                                                                        strong: true,
                                                                      ),
                                                                    ],
                                                                  ],
                                                                ),
                                                                const SizedBox(height: 6),
                                                                Wrap(
                                                                  spacing: 8,
                                                                  runSpacing: 8,
                                                                  crossAxisAlignment: WrapCrossAlignment.center,
                                                                  children: [
                                                                    if (distLabel != null) _chip(distLabel),
                                                                    _gateChipFrom(gate, myUid, cooling: cooling),
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
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
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
