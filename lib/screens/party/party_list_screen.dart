/*
 * lib/screens/party/party_list_screen.dart
 *
 * Lists Party members from:
 *   /users/{uid}/party/{otherUid}
 *
 * No schema changes.
 */

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/chat_service.dart";
import "package:prox/services/meetup_service.dart";
import "package:prox/services/keyword_moderation_service.dart";
import "package:prox/services/keyword_quality_service.dart";
import "package:prox/services/party_service.dart";
import "package:prox/services/user_profile_service.dart";
import "package:prox/utils/bounded_async_map.dart";
import "package:prox/screens/party/party_member_profile_screen.dart";

class PartyListScreen extends StatelessWidget {
  const PartyListScreen({super.key});

  static Set<String> visibleRelationshipUids({
    required Iterable<String> partyUids,
    required Iterable<String> referredByMeUids,
    required Iterable<String> referredMeUids,
    required Iterable<String> incomingRequestUids,
    required Iterable<String> outgoingRequestUids,
    required String myUid,
  }) {
    final me = myUid.trim();
    // Only accepted entries in the canonical Party subcollection are members.
    // Referrals and requests remain relationship signals until explicitly added.
    return <String>{...partyUids}
        .map((uid) => uid.trim())
        .where((uid) => uid.isNotEmpty && uid != me)
        .toSet();
  }

  static String? inPersonPartyReferralUid({
    required String docId,
    required Map<String, dynamic> data,
  }) {
    if (data["partyInPersonQrRequested"] != true) return null;
    final uid = (data["uid"] ?? docId).toString().trim();
    return uid.isEmpty ? null : uid;
  }

  static String? inPersonPartyReferrerUid({
    required String referrerUid,
    required Map<String, dynamic> data,
    required String myUid,
  }) {
    final referrer = referrerUid.trim();
    if (data["partyInPersonQrRequested"] != true) return null;
    if (referrer.isEmpty || referrer == myUid.trim()) return null;
    return referrer;
  }

  Future<Map<String, UserProfile>> _loadProfilesForUids(
    Iterable<String> uids,
  ) async {
    final cleanUids = uids
        .map((uid) => uid.trim())
        .where((uid) => uid.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (cleanUids.isEmpty) return <String, UserProfile>{};

    final docs = await boundedAsyncMap(
      cleanUids,
      (uid) => FirebaseFirestore.instance
          .collection("publicProfiles")
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 8)),
    );

    final profiles = <String, UserProfile>{};
    for (final doc in docs) {
      final uid = doc.id.trim();
      final data = doc.data();
      if (uid.isEmpty || data == null) continue;
      profiles[uid] = UserProfile.fromMap(uid, data);
    }
    return profiles;
  }

  Widget _keywordEntryCard(
    BuildContext context, {
    required ThemeData theme,
    required ColorScheme cs,
    required List<PartyMemberEntry> entries,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Card(
        elevation: 0,
        color: cs.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Party keyword browser",
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "See aggregate wants, offers, and useful connections across confirmed Party members.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (entries.isNotEmpty) ...[
                const SizedBox(height: 10),
                StreamBuilder<Set<String>>(
                  stream: KeywordModerationService.instance
                      .watchSuppressedKeywords(),
                  builder: (context, moderationSnap) =>
                      FutureBuilder<Map<String, UserProfile>>(
                        future: _loadProfilesForUids(
                          entries.map((entry) => entry.otherUid),
                        ),
                        builder: (context, snapshot) {
                          final profiles =
                              snapshot.data ?? const <String, UserProfile>{};
                          final suppressed =
                              moderationSnap.data ?? const <String>{};
                          final counts = <String, int>{};
                          for (final profile in profiles.values) {
                            for (final raw in <String>[
                              ...profile.searchingFor,
                              ...profile.canProvide,
                            ]) {
                              final keyword = raw.trim().toLowerCase();
                              if (KeywordQualityService.validate(
                                    keyword,
                                  ).isValid &&
                                  !suppressed.contains(keyword)) {
                                counts[keyword] = (counts[keyword] ?? 0) + 1;
                              }
                            }
                          }
                          final hot = counts.entries.toList(growable: false)
                            ..sort((a, b) {
                              final byCount = b.value.compareTo(a.value);
                              return byCount != 0
                                  ? byCount
                                  : a.key.compareTo(b.key);
                            });
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const LinearProgressIndicator();
                          }
                          if (hot.isEmpty) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                "Hot now",
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: hot
                                    .take(5)
                                    .map(
                                      (row) => ActionChip(
                                        onPressed: () => _browseKeyword(
                                          context,
                                          keyword: row.key,
                                          profiles: profiles,
                                        ),
                                        avatar: const Icon(
                                          Icons.local_fire_department_outlined,
                                          size: 16,
                                        ),
                                        label: Text(
                                          "${row.key} (${row.value})",
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                            ],
                          );
                        },
                      ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: entries.isEmpty
                          ? null
                          : () => _showPartyInsights(context, entries),
                      icon: const Icon(Icons.leaderboard_outlined),
                      label: const Text("Top keywords"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showNetworkReach(context),
                      icon: const Icon(Icons.hub_outlined),
                      label: const Text("Network reach"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _browseKeyword(
    BuildContext context, {
    required String keyword,
    required Map<String, UserProfile> profiles,
  }) async {
    final normalized = keyword.trim().toLowerCase();
    final rows = <({String uid, UserProfile profile, String role})>[];
    for (final entry in profiles.entries) {
      if (entry.value.searchingFor.any(
        (value) => value.trim().toLowerCase() == normalized,
      )) {
        rows.add((uid: entry.key, profile: entry.value, role: "wants"));
      }
      if (entry.value.canProvide.any(
        (value) => value.trim().toLowerCase() == normalized,
      )) {
        rows.add((uid: entry.key, profile: entry.value, role: "has"));
      }
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: <Widget>[
            Text(keyword, style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text("${rows.length} Party keyword entries"),
            const SizedBox(height: 12),
            for (final row in rows)
              ListTile(
                leading: CircleAvatar(
                  backgroundImage:
                      (row.profile.photoUrl ?? "").trim().isNotEmpty
                      ? NetworkImage(row.profile.photoUrl!.trim())
                      : null,
                  child: (row.profile.photoUrl ?? "").trim().isEmpty
                      ? const Icon(Icons.person_outline)
                      : null,
                ),
                title: Text(
                  (row.profile.displayName ?? "").trim().isNotEmpty
                      ? row.profile.displayName!.trim()
                      : _uidFallback(row.uid),
                ),
                subtitle: Text(row.role == "wants" ? "Wants" : "Has"),
                onTap: () => _openMember(context, row.uid),
                trailing: IconButton(
                  tooltip: "Report keyword",
                  icon: const Icon(Icons.flag_outlined),
                  onPressed: () async {
                    final report = await showDialog<bool>(
                      context: sheetContext,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text("Report this keyword?"),
                        content: const Text(
                          "Use this for fake, misleading, offensive, or meaningless keywords. It will be hidden from your Party view immediately.",
                        ),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: const Text("Cancel"),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: const Text("Report and hide"),
                          ),
                        ],
                      ),
                    );
                    if (report != true) return;
                    await KeywordModerationService.instance.report(
                      keyword: keyword,
                      targetUid: row.uid,
                      role: row.role,
                    );
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPartyInsights(
    BuildContext context,
    List<PartyMemberEntry> entries,
  ) async {
    final profiles = await _loadProfilesForUids(
      entries.map((entry) => entry.otherUid),
    );
    final suppressed = await KeywordModerationService.instance
        .watchSuppressedKeywords()
        .first;
    if (!context.mounted) return;

    final wants = <String, int>{};
    final offers = <String, int>{};
    for (final profile in profiles.values) {
      for (final raw in profile.searchingFor) {
        final keyword = raw.trim().toLowerCase();
        if (KeywordQualityService.validate(keyword).isValid &&
            !suppressed.contains(keyword)) {
          wants[keyword] = (wants[keyword] ?? 0) + 1;
        }
      }
      for (final raw in profile.canProvide) {
        final keyword = raw.trim().toLowerCase();
        if (KeywordQualityService.validate(keyword).isValid &&
            !suppressed.contains(keyword)) {
          offers[keyword] = (offers[keyword] ?? 0) + 1;
        }
      }
    }

    final freshWants = <String, int>{};
    final freshOffers = <String, int>{};
    final recentCutoff = DateTime.now().subtract(const Duration(days: 14));
    final freshDocs = await boundedAsyncMap(
      entries,
      (entry) => FirebaseFirestore.instance
          .collection("publicProfiles")
          .doc(entry.otherUid)
          .get()
          .timeout(const Duration(seconds: 8)),
    );
    for (final doc in freshDocs) {
      final data = doc.data();
      final updatedAt = data?["updatedAt"];
      if (data == null ||
          updatedAt is! Timestamp ||
          updatedAt.toDate().isBefore(recentCutoff)) {
        continue;
      }
      final profile = UserProfile.fromMap(doc.id, data);
      for (final raw in profile.searchingFor) {
        final keyword = raw.trim().toLowerCase();
        if (KeywordQualityService.validate(keyword).isValid &&
            !suppressed.contains(keyword)) {
          freshWants[keyword] = (freshWants[keyword] ?? 0) + 1;
        }
      }
      for (final raw in profile.canProvide) {
        final keyword = raw.trim().toLowerCase();
        if (KeywordQualityService.validate(keyword).isValid &&
            !suppressed.contains(keyword)) {
          freshOffers[keyword] = (freshOffers[keyword] ?? 0) + 1;
        }
      }
    }

    List<MapEntry<String, int>> top(Map<String, int> source) {
      final rows = source.entries.toList(growable: false)
        ..sort((a, b) {
          final count = b.value.compareTo(a.value);
          return count != 0 ? count : a.key.compareTo(b.key);
        });
      return rows.take(8).toList(growable: false);
    }

    final connections =
        wants.keys
            .where(offers.containsKey)
            .map(
              (keyword) => MapEntry<String, int>(
                keyword,
                (wants[keyword] ?? 0) * (offers[keyword] ?? 0),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => b.value.compareTo(a.value));

    Widget section(String title, List<MapEntry<String, int>> rows) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          if (rows.isEmpty)
            const Text("No shared keywords yet.")
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: rows
                  .map((row) => Chip(label: Text("${row.key} (${row.value})")))
                  .toList(growable: false),
            ),
        ],
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                "Party insights",
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text("Based on ${profiles.length} confirmed Party profiles."),
              const SizedBox(height: 18),
              section("Connection opportunities", connections.take(8).toList()),
              const SizedBox(height: 18),
              section("New requests", top(freshWants)),
              const SizedBox(height: 18),
              section("New offers", top(freshOffers)),
              const SizedBox(height: 18),
              section("Hot requests", top(wants)),
              const SizedBox(height: 18),
              section("Hot offers", top(offers)),
            ],
          ),
        ),
      ),
    );
  }

  void _showNetworkReach(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                "Private network reach",
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text(
                "Share only anonymous keyword aggregates with Party connections. Names, user IDs, and contact lists are never included.",
              ),
              const SizedBox(height: 12),
              StreamBuilder<bool>(
                stream: PartyService.instance.watchPartyNetworkSharing(),
                builder: (context, snapshot) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Contribute anonymous insights"),
                  subtitle: const Text(
                    "Both the connector and profile owner must enable sharing.",
                  ),
                  value: snapshot.data == true,
                  onChanged: PartyService.instance.setPartyNetworkSharing,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: PartyService.instance.refreshPartyNetworkInsights,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Refresh private insights"),
                ),
              ),
              const SizedBox(height: 16),
              StreamBuilder<Map<String, dynamic>>(
                stream: PartyService.instance.watchPartyNetworkInsights(),
                builder: (context, snapshot) {
                  final data = snapshot.data ?? const <String, dynamic>{};
                  if (data["status"] == "requested") {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final raw = data["result"];
                  final result = raw is Map
                      ? Map<String, dynamic>.from(raw)
                      : const <String, dynamic>{};
                  if (result.isEmpty) {
                    return const Text(
                      "Refresh to calculate your current reach.",
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        "${result["directMembers"] ?? 0} direct members | "
                        "${result["sharingConnectors"] ?? 0} sharing connections | "
                        "${result["secondDegreeProfiles"] ?? 0} anonymous profiles",
                      ),
                      const SizedBox(height: 14),
                      _networkAggregate(
                        "Opportunities",
                        result["opportunities"],
                      ),
                      const SizedBox(height: 12),
                      _networkAggregate("Most requested", result["topWants"]),
                      const SizedBox(height: 12),
                      _networkAggregate("Most available", result["topOffers"]),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _networkAggregate(String title, dynamic raw) {
    final rows = raw is List
        ? raw.whereType<Map>().toList(growable: false)
        : const <Map>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (rows.isEmpty)
          const Text("No consenting aggregate data yet.")
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: rows
                .map((row) {
                  return Chip(
                    label: Text(
                      "${row["keyword"] ?? ""} (${row["count"] ?? 0})",
                    ),
                  );
                })
                .toList(growable: false),
          ),
      ],
    );
  }

  Widget _incomingRequestsNoticeCard(
    BuildContext context, {
    required ThemeData theme,
    required ColorScheme cs,
    required int count,
  }) {
    if (count <= 0) return const SizedBox.shrink();

    final String noun = count == 1 ? "request" : "requests";
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Card(
        elevation: 0,
        color: cs.secondaryContainer.withValues(alpha: 0.7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.secondary.withValues(alpha: 0.45)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.notifications_active_outlined,
                color: cs.onSecondaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "$count party add $noun waiting for review.",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMember(BuildContext context, String otherUid) {
    final previous = ContextHelpService.instance.contextKey.value;
    ContextHelpService.instance.setContext("party:member_profile");
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => PartyMemberProfileScreen(memberUid: otherUid),
          ),
        )
        .then((_) {
          ContextHelpService.instance.setContext(previous);
        });
  }

  Future<String?> _ensureChat(BuildContext context, String uid) async {
    try {
      return await ChatService.instance.ensureDirectChat(uid);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Could not open chat.")));
      }
      return null;
    }
  }

  Future<void> _messageMember(BuildContext context, String uid) async {
    final chatId = await _ensureChat(context, uid);
    if (chatId == null || !context.mounted) return;
    Navigator.of(context).pushNamed(
      "/chat",
      arguments: <String, String>{"chatId": chatId, "otherUid": uid},
    );
  }

  Future<void> _requestMeetup(
    BuildContext context,
    String uid, {
    required bool online,
  }) async {
    if (!online) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Meetup requests can only be sent to online members."),
        ),
      );
      return;
    }
    final chatId = await _ensureChat(context, uid);
    if (chatId == null) return;
    try {
      await MeetupService.instance.requestMeetup(chatId: chatId, otherUid: uid);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Meetup request sent.")));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("They are offline now. Meetup request not sent."),
          ),
        );
      }
    }
  }

  String _uidFallback(String uid) {
    final s = uid.trim();
    if (s.isEmpty) return "Prox user";
    final n = s.length >= 6 ? 6 : s.length;
    return "User ${s.substring(0, n)}";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? "";

    return StreamBuilder<List<PartyMemberEntry>>(
      stream: PartyService.instance.watchMyPartyEntries(),
      builder: (context, snap) {
        final entries = snap.data ?? const <PartyMemberEntry>[];
        final Map<String, PartyMemberEntry> partyByUid =
            <String, PartyMemberEntry>{
              for (final e in entries) e.otherUid.trim(): e,
            };

        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Card(
              elevation: 0,
              color: cs.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Party list unavailable",
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "We could not load Party members right now. Pull to refresh or reopen this tab.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return StreamBuilder<List<PartyAddRequest>>(
          stream: PartyService.instance.watchIncomingPartyAddRequests(),
          builder: (context, incomingRequestSnap) {
            final incomingRequests =
                incomingRequestSnap.data ?? const <PartyAddRequest>[];
            final Set<String> incomingRequestUids = incomingRequests
                .map((r) => r.fromUid.trim())
                .where((uid) => uid.isNotEmpty)
                .toSet();

            return StreamBuilder<List<PartyAddRequest>>(
              stream: PartyService.instance.watchOutgoingPartyAddRequests(),
              builder: (context, outgoingRequestSnap) {
                final outgoingRequests =
                    outgoingRequestSnap.data ?? const <PartyAddRequest>[];
                final Set<String> outgoingRequestUids = outgoingRequests
                    .map((r) => r.toUid.trim())
                    .where((uid) => uid.isNotEmpty)
                    .toSet();

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: myUid.trim().isEmpty
                      ? null
                      : FirebaseFirestore.instance
                            .collection("users")
                            .doc(myUid)
                            .collection("referrals")
                            .snapshots(),
                  builder: (context, myReferralsSnap) {
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: myUid.trim().isEmpty
                          ? null
                          : FirebaseFirestore.instance
                                .collectionGroup("referrals")
                                .where("uid", isEqualTo: myUid)
                                .limit(20)
                                .snapshots(),
                      builder: (context, referredBySnap) {
                        final Set<String> referredByMeUids = <String>{};
                        final referralDocs =
                            myReferralsSnap.data?.docs ??
                            const <
                              QueryDocumentSnapshot<Map<String, dynamic>>
                            >[];
                        for (final doc in referralDocs) {
                          final uid = inPersonPartyReferralUid(
                            docId: doc.id,
                            data: doc.data(),
                          );
                          if (uid != null) referredByMeUids.add(uid);
                        }

                        final Set<String> referredMeUids = <String>{};
                        final referredByDocs =
                            referredBySnap.data?.docs ??
                            const <
                              QueryDocumentSnapshot<Map<String, dynamic>>
                            >[];
                        for (final doc in referredByDocs) {
                          final referrerUid = inPersonPartyReferrerUid(
                            referrerUid: doc.reference.parent.parent?.id ?? "",
                            data: doc.data(),
                            myUid: myUid,
                          );
                          if (referrerUid != null) {
                            referredMeUids.add(referrerUid);
                          }
                        }

                        final Set<String> visibleUidSet =
                            visibleRelationshipUids(
                              partyUids: partyByUid.keys,
                              referredByMeUids: referredByMeUids,
                              referredMeUids: referredMeUids,
                              incomingRequestUids: incomingRequestUids,
                              outgoingRequestUids: outgoingRequestUids,
                              myUid: myUid,
                            );

                        final List<String> visibleUids =
                            visibleUidSet.toList(growable: true)..sort((a, b) {
                              final ea = partyByUid[a];
                              final eb = partyByUid[b];
                              if (ea != null && eb == null) return -1;
                              if (ea == null && eb != null) return 1;
                              if (ea != null && eb != null) {
                                final ad = ea.since;
                                final bd = eb.since;
                                if (ad == null && bd != null) return 1;
                                if (ad != null && bd == null) return -1;
                                if (ad != null && bd != null) {
                                  final cmp = bd.compareTo(ad);
                                  if (cmp != 0) return cmp;
                                }
                              }

                              return a.compareTo(b);
                            });

                        if (visibleUids.isEmpty) {
                          final bool waiting =
                              snap.connectionState == ConnectionState.waiting ||
                              incomingRequestSnap.connectionState ==
                                  ConnectionState.waiting ||
                              outgoingRequestSnap.connectionState ==
                                  ConnectionState.waiting ||
                              myReferralsSnap.connectionState ==
                                  ConnectionState.waiting ||
                              referredBySnap.connectionState ==
                                  ConnectionState.waiting;
                          return Column(
                            children: [
                              _keywordEntryCard(
                                context,
                                theme: theme,
                                cs: cs,
                                entries: entries,
                              ),
                              _incomingRequestsNoticeCard(
                                context,
                                theme: theme,
                                cs: cs,
                                count: incomingRequestUids.length,
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  6,
                                  16,
                                  16,
                                ),
                                child: Card(
                                  elevation: 0,
                                  color: cs.surfaceContainerHighest,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color: cs.outlineVariant.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      waiting
                                          ? "Loading members..."
                                          : "No members found yet.",
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        return FutureBuilder<Map<String, UserProfile>>(
                          future: _loadProfilesForUids(visibleUids),
                          builder: (context, profileSnap) {
                            final profileByUid =
                                profileSnap.data ??
                                const <String, UserProfile>{};
                            return StreamBuilder<Set<String>>(
                              stream: PartyService.instance
                                  .watchOnlinePartyUids(visibleUids),
                              builder: (context, presenceSnap) {
                                final onlineUids =
                                    presenceSnap.data ?? const <String>{};
                                final sortedUids =
                                    List<String>.from(visibleUids)..sort((
                                      a,
                                      b,
                                    ) {
                                      final onlineOrder =
                                          (onlineUids.contains(b) ? 1 : 0) -
                                          (onlineUids.contains(a) ? 1 : 0);
                                      if (onlineOrder != 0) return onlineOrder;
                                      final aName =
                                          profileByUid[a]?.displayName
                                              ?.toLowerCase() ??
                                          a;
                                      final bName =
                                          profileByUid[b]?.displayName
                                              ?.toLowerCase() ??
                                          b;
                                      return aName.compareTo(bName);
                                    });
                                return Column(
                                  children: [
                                    _keywordEntryCard(
                                      context,
                                      theme: theme,
                                      cs: cs,
                                      entries: entries,
                                    ),
                                    _incomingRequestsNoticeCard(
                                      context,
                                      theme: theme,
                                      cs: cs,
                                      count: incomingRequestUids.length,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        4,
                                        16,
                                        6,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          "${onlineUids.length} online | ${sortedUids.length - onlineUids.length} offline",
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      ),
                                    ),
                                    ListView.separated(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(
                                        8,
                                        2,
                                        8,
                                        12,
                                      ),
                                      itemCount: sortedUids.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 2),
                                      itemBuilder: (context, i) {
                                        final uid = sortedUids[i];
                                        final online = onlineUids.contains(uid);
                                        final e = partyByUid[uid];
                                        final p = profileByUid[uid];
                                        final inParty = e != null;
                                        final referredByMe = referredByMeUids
                                            .contains(uid);
                                        final referredMe = referredMeUids
                                            .contains(uid);
                                        final hasIncomingRequest =
                                            incomingRequestUids.contains(uid);
                                        final hasOutgoingRequest =
                                            outgoingRequestUids.contains(uid);
                                        final hasReferralRelationship =
                                            referredByMe || referredMe;

                                        final String name =
                                            (p?.displayName ?? "")
                                                .trim()
                                                .isNotEmpty
                                            ? p!.displayName!.trim()
                                            : _uidFallback(uid);
                                        final String photoUrl =
                                            (p?.photoUrl ?? "").trim();

                                        Color cardColor =
                                            cs.surfaceContainerHighest;
                                        Color borderColor = cs.outlineVariant
                                            .withValues(alpha: 0.55);
                                        Color nameColor =
                                            theme.textTheme.titleSmall?.color ??
                                            cs.onSurface;

                                        if (hasIncomingRequest) {
                                          cardColor = cs.secondaryContainer
                                              .withValues(alpha: 0.55);
                                          borderColor = cs.secondary.withValues(
                                            alpha: 0.55,
                                          );
                                          nameColor = cs.onSecondaryContainer;
                                        } else if (hasReferralRelationship) {
                                          cardColor = cs.tertiaryContainer
                                              .withValues(alpha: 0.5);
                                          borderColor = cs.tertiary.withValues(
                                            alpha: 0.55,
                                          );
                                          nameColor = cs.onTertiaryContainer;
                                        }

                                        Widget actionButton;
                                        if (inParty) {
                                          actionButton = PopupMenuButton<String>(
                                            tooltip: "Party member actions",
                                            onSelected: (action) async {
                                              if (action == "message") {
                                                await _messageMember(
                                                  context,
                                                  uid,
                                                );
                                                return;
                                              }
                                              if (action == "meetup") {
                                                await _requestMeetup(
                                                  context,
                                                  uid,
                                                  online: online,
                                                );
                                                return;
                                              }
                                              if (action != "remove") return;
                                              final bool?
                                              ok = await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  title: const Text(
                                                    "Remove from Party?",
                                                  ),
                                                  content: const Text(
                                                    "Are you sure? You can add them again later.",
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                            ctx,
                                                            false,
                                                          ),
                                                      child: const Text(
                                                        "Cancel",
                                                      ),
                                                    ),
                                                    FilledButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                            ctx,
                                                            true,
                                                          ),
                                                      child: const Text(
                                                        "Remove",
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (ok != true) return;

                                              await PartyService.instance
                                                  .removeFromParty(uid);
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      "Removed from Party",
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                            itemBuilder: (context) =>
                                                <PopupMenuEntry<String>>[
                                                  const PopupMenuItem<String>(
                                                    value: "message",
                                                    child: ListTile(
                                                      leading: Icon(
                                                        Icons.chat_outlined,
                                                      ),
                                                      title: Text("Message"),
                                                      contentPadding:
                                                          EdgeInsets.zero,
                                                    ),
                                                  ),
                                                  PopupMenuItem<String>(
                                                    value: "meetup",
                                                    enabled: online,
                                                    child: ListTile(
                                                      leading: const Icon(
                                                        Icons
                                                            .handshake_outlined,
                                                      ),
                                                      title: const Text(
                                                        "Request meetup",
                                                      ),
                                                      subtitle: online
                                                          ? null
                                                          : const Text(
                                                              "Offline",
                                                            ),
                                                      contentPadding:
                                                          EdgeInsets.zero,
                                                    ),
                                                  ),
                                                  const PopupMenuDivider(),
                                                  const PopupMenuItem<String>(
                                                    value: "remove",
                                                    child: ListTile(
                                                      leading: Icon(
                                                        Icons
                                                            .person_remove_outlined,
                                                      ),
                                                      title: Text(
                                                        "Remove from Party",
                                                      ),
                                                      contentPadding:
                                                          EdgeInsets.zero,
                                                    ),
                                                  ),
                                                ],
                                          );
                                        } else if (hasIncomingRequest) {
                                          actionButton = FilledButton.tonalIcon(
                                            onPressed: () async {
                                              await PartyService.instance
                                                  .acceptPartyAddRequestFrom(
                                                    uid,
                                                  );
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      "Party request accepted.",
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.person_add_alt_1_outlined,
                                            ),
                                            label: const Text("Accept"),
                                          );
                                        } else if (hasOutgoingRequest) {
                                          actionButton = FilledButton.tonalIcon(
                                            onPressed: null,
                                            icon: const Icon(
                                              Icons.outgoing_mail,
                                            ),
                                            label: const Text("Sent"),
                                          );
                                        } else {
                                          actionButton = OutlinedButton.icon(
                                            onPressed: () async {
                                              await PartyService.instance
                                                  .requestPartyAdd(uid);
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      "Party add request sent.",
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.send_outlined,
                                            ),
                                            label: const Text("Request"),
                                          );
                                        }

                                        return Card(
                                          elevation: 0,
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          color: cardColor,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            side: BorderSide(
                                              color: borderColor,
                                            ),
                                          ),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            onTap: () async {
                                              if (!inParty) return;
                                              // ignore: discarded_futures
                                              PartyService.instance
                                                  .reconcileMutual(uid);
                                              _openMember(context, uid);
                                            },
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    12,
                                                    10,
                                                    12,
                                                    10,
                                                  ),
                                              child: Row(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 18,
                                                    backgroundImage:
                                                        photoUrl.isNotEmpty
                                                        ? NetworkImage(photoUrl)
                                                        : null,
                                                    child: photoUrl.isEmpty
                                                        ? const Icon(
                                                            Icons.person,
                                                            size: 18,
                                                          )
                                                        : null,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          name,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: theme
                                                              .textTheme
                                                              .titleSmall
                                                              ?.copyWith(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                                color:
                                                                    nameColor,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 6,
                                                        ),
                                                        Wrap(
                                                          spacing: 8,
                                                          runSpacing: 6,
                                                          children: [
                                                            _RelationshipPill(
                                                              icon: online
                                                                  ? Icons.circle
                                                                  : Icons
                                                                        .circle_outlined,
                                                              label: online
                                                                  ? "Online"
                                                                  : "Offline",
                                                              bg: online
                                                                  ? cs.primaryContainer
                                                                  : cs.surfaceContainer,
                                                              fg: online
                                                                  ? cs.onPrimaryContainer
                                                                  : cs.onSurfaceVariant,
                                                              border: online
                                                                  ? cs.primary
                                                                  : cs.outline,
                                                            ),
                                                            if (referredMe)
                                                              _RelationshipPill(
                                                                icon: Icons
                                                                    .person_search_outlined,
                                                                label:
                                                                    "Referred You",
                                                                bg: cs
                                                                    .secondaryContainer,
                                                                fg: cs
                                                                    .onSecondaryContainer,
                                                                border: cs
                                                                    .secondary
                                                                    .withValues(
                                                                      alpha:
                                                                          0.45,
                                                                    ),
                                                              ),
                                                            if (referredByMe)
                                                              _RelationshipPill(
                                                                icon: Icons
                                                                    .campaign_outlined,
                                                                label:
                                                                    "Your Referral",
                                                                bg: cs
                                                                    .primaryContainer,
                                                                fg: cs
                                                                    .onPrimaryContainer,
                                                                border: cs
                                                                    .primary
                                                                    .withValues(
                                                                      alpha:
                                                                          0.45,
                                                                    ),
                                                              ),
                                                            if (hasIncomingRequest)
                                                              _RelationshipPill(
                                                                icon: Icons
                                                                    .mark_email_unread_outlined,
                                                                label:
                                                                    "Requested You",
                                                                bg: cs
                                                                    .secondaryContainer,
                                                                fg: cs
                                                                    .onSecondaryContainer,
                                                                border: cs
                                                                    .secondary
                                                                    .withValues(
                                                                      alpha:
                                                                          0.45,
                                                                    ),
                                                              ),
                                                            if (!hasIncomingRequest &&
                                                                hasOutgoingRequest)
                                                              _RelationshipPill(
                                                                icon: Icons
                                                                    .outgoing_mail,
                                                                label:
                                                                    "Request Sent",
                                                                bg: cs
                                                                    .tertiaryContainer,
                                                                fg: cs
                                                                    .onTertiaryContainer,
                                                                border: cs
                                                                    .tertiary
                                                                    .withValues(
                                                                      alpha:
                                                                          0.45,
                                                                    ),
                                                              ),
                                                            if (e?.mutual ==
                                                                true)
                                                              const _MutualPill(),
                                                            if (inParty &&
                                                                e.mutual !=
                                                                    true)
                                                              Container(
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          8,
                                                                      vertical:
                                                                          3,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color: cs
                                                                      .primaryContainer,
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        999,
                                                                      ),
                                                                ),
                                                                child: Text(
                                                                  "In Party",
                                                                  style: theme
                                                                      .textTheme
                                                                      .labelSmall
                                                                      ?.copyWith(
                                                                        fontWeight:
                                                                            FontWeight.w700,
                                                                        color: cs
                                                                            .onPrimaryContainer,
                                                                      ),
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                        if (e?.since !=
                                                            null) ...[
                                                          const SizedBox(
                                                            height: 6,
                                                          ),
                                                          Text(
                                                            "Added: ${_friendlyDate(e!.since!)}",
                                                            style: theme
                                                                .textTheme
                                                                .bodySmall
                                                                ?.copyWith(
                                                                  color: cs
                                                                      .onSurfaceVariant,
                                                                ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  actionButton,
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
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
        );
      },
    );
  }

  static String _friendlyDate(DateTime dt) {
    final d = dt.toLocal();
    final y = d.year.toString().padLeft(4, "0");
    final m = d.month.toString().padLeft(2, "0");
    final day = d.day.toString().padLeft(2, "0");
    return "$m/$day/$y";
  }
}

class _MutualPill extends StatelessWidget {
  const _MutualPill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.secondary.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group, size: 14, color: cs.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            "Mutual",
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _RelationshipPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  final Color border;

  const _RelationshipPill({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
