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
import "package:prox/services/party_service.dart";
import "package:prox/services/user_profile_service.dart";

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
    return <String>{
      ...partyUids,
      ...referredByMeUids,
      ...referredMeUids,
      ...incomingRequestUids,
      ...outgoingRequestUids,
    }
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

    final docs = await Future.wait(
      cleanUids.map(
        (uid) =>
            FirebaseFirestore.instance.collection("profiles").doc(uid).get(),
      ),
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
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                "See top 'want' and 'can provide' keywords across your party, then open message or meetup from each keyword.",
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                "Party keyword browser is not available in this build."),
                          ),
                        );
                      },
                      icon: const Icon(Icons.leaderboard_outlined),
                      label: const Text("Top keywords"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                "Private Party notes are not available in this build."),
                          ),
                        );
                      },
                      icon: const Icon(Icons.sticky_note_2_outlined),
                      label: const Text("Private notes"),
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
              Icon(Icons.notifications_active_outlined,
                  color: cs.onSecondaryContainer),
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
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Party member"),
        content: Text("Member ID: ${_uidFallback(otherUid)}"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Close"),
          ),
        ],
      ),
    ).then((_) {
      ContextHelpService.instance.setContext(previous);
    });
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
                side:
                    BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Party list unavailable",
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "We could not load Party members right now. Pull to refresh or reopen this tab.",
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
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
                        final referralDocs = myReferralsSnap.data?.docs ??
                            const <QueryDocumentSnapshot<
                                Map<String, dynamic>>>[];
                        for (final doc in referralDocs) {
                          final uid = inPersonPartyReferralUid(
                            docId: doc.id,
                            data: doc.data(),
                          );
                          if (uid != null) referredByMeUids.add(uid);
                        }

                        final Set<String> referredMeUids = <String>{};
                        final referredByDocs = referredBySnap.data?.docs ??
                            const <QueryDocumentSnapshot<
                                Map<String, dynamic>>>[];
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
                            visibleUidSet.toList(growable: true)
                              ..sort((a, b) {
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
                              _keywordEntryCard(context,
                                  theme: theme, cs: cs, entries: entries),
                              _incomingRequestsNoticeCard(
                                context,
                                theme: theme,
                                cs: cs,
                                count: incomingRequestUids.length,
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 6, 16, 16),
                                child: Card(
                                  elevation: 0,
                                  color: cs.surfaceContainerHighest,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                        color: cs.outlineVariant
                                            .withValues(alpha: 0.6)),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      waiting
                                          ? "Loading members..."
                                          : "No members found yet.",
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                              color: cs.onSurfaceVariant),
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
                            final profileByUid = profileSnap.data ??
                                const <String, UserProfile>{};
                            return Column(
                              children: [
                                _keywordEntryCard(context,
                                    theme: theme, cs: cs, entries: entries),
                                _incomingRequestsNoticeCard(
                                  context,
                                  theme: theme,
                                  cs: cs,
                                  count: incomingRequestUids.length,
                                ),
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  padding:
                                      const EdgeInsets.fromLTRB(8, 2, 8, 12),
                                  itemCount: visibleUids.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 2),
                                  itemBuilder: (context, i) {
                                    final uid = visibleUids[i];
                                    final e = partyByUid[uid];
                                    final p = profileByUid[uid];
                                    final inParty = e != null;
                                    final referredByMe =
                                        referredByMeUids.contains(uid);
                                    final referredMe =
                                        referredMeUids.contains(uid);
                                    final hasIncomingRequest =
                                        incomingRequestUids.contains(uid);
                                    final hasOutgoingRequest =
                                        outgoingRequestUids.contains(uid);
                                    final hasReferralRelationship =
                                        referredByMe || referredMe;

                                    final String name =
                                        (p?.displayName ?? "").trim().isNotEmpty
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
                                      borderColor =
                                          cs.secondary.withValues(alpha: 0.55);
                                      nameColor = cs.onSecondaryContainer;
                                    } else if (hasReferralRelationship) {
                                      cardColor = cs.tertiaryContainer
                                          .withValues(alpha: 0.5);
                                      borderColor =
                                          cs.tertiary.withValues(alpha: 0.55);
                                      nameColor = cs.onTertiaryContainer;
                                    }

                                    Widget actionButton;
                                    if (inParty) {
                                      actionButton = IconButton(
                                        tooltip: "Remove from Party",
                                        icon: const Icon(
                                            Icons.person_remove_outlined),
                                        onPressed: () async {
                                          final bool? ok =
                                              await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text(
                                                  "Remove from Party?"),
                                              content: const Text(
                                                  "Are you sure? You can add them again later."),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, false),
                                                  child: const Text("Cancel"),
                                                ),
                                                FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, true),
                                                  child: const Text("Remove"),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (ok != true) return;

                                          await PartyService.instance
                                              .removeFromParty(uid);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                  content: Text(
                                                      "Removed from Party")),
                                            );
                                          }
                                        },
                                      );
                                    } else if (hasIncomingRequest) {
                                      actionButton = FilledButton.tonalIcon(
                                        onPressed: () async {
                                          await PartyService.instance
                                              .acceptPartyAddRequestFrom(uid);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    "Party request accepted."),
                                              ),
                                            );
                                          }
                                        },
                                        icon: const Icon(
                                            Icons.person_add_alt_1_outlined),
                                        label: const Text("Accept"),
                                      );
                                    } else if (hasOutgoingRequest) {
                                      actionButton = FilledButton.tonalIcon(
                                        onPressed: null,
                                        icon: const Icon(Icons.outgoing_mail),
                                        label: const Text("Sent"),
                                      );
                                    } else {
                                      actionButton = OutlinedButton.icon(
                                        onPressed: () async {
                                          await PartyService.instance
                                              .requestPartyAdd(uid);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    "Party add request sent."),
                                              ),
                                            );
                                          }
                                        },
                                        icon: const Icon(Icons.send_outlined),
                                        label: const Text("Request"),
                                      );
                                    }

                                    return Card(
                                      elevation: 0,
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      color: cardColor,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        side: BorderSide(color: borderColor),
                                      ),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: () async {
                                          if (inParty) {
                                            // ignore: discarded_futures
                                            PartyService.instance
                                                .reconcileMutual(uid);
                                          }
                                          _openMember(context, uid);
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              12, 10, 12, 10),
                                          child: Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 18,
                                                backgroundImage:
                                                    photoUrl.isNotEmpty
                                                        ? NetworkImage(photoUrl)
                                                        : null,
                                                child: photoUrl.isEmpty
                                                    ? const Icon(Icons.person,
                                                        size: 18)
                                                    : null,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      name,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: theme
                                                          .textTheme.titleSmall
                                                          ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: nameColor,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Wrap(
                                                      spacing: 8,
                                                      runSpacing: 6,
                                                      children: [
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
                                                            border: cs.secondary
                                                                .withValues(
                                                                    alpha:
                                                                        0.45),
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
                                                            border: cs.primary
                                                                .withValues(
                                                                    alpha:
                                                                        0.45),
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
                                                            border: cs.secondary
                                                                .withValues(
                                                                    alpha:
                                                                        0.45),
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
                                                            border: cs.tertiary
                                                                .withValues(
                                                                    alpha:
                                                                        0.45),
                                                          ),
                                                        if (e?.mutual == true)
                                                          const _MutualPill(),
                                                        if (inParty &&
                                                            e.mutual != true)
                                                          Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        8,
                                                                    vertical:
                                                                        3),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: cs
                                                                  .primaryContainer,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          999),
                                                            ),
                                                            child: Text(
                                                              "In Party",
                                                              style: theme
                                                                  .textTheme
                                                                  .labelSmall
                                                                  ?.copyWith(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: cs
                                                                    .onPrimaryContainer,
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    if (e?.since != null) ...[
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        "Added: ${_friendlyDate(e!.since!)}",
                                                        style: theme
                                                            .textTheme.bodySmall
                                                            ?.copyWith(
                                                                color: cs
                                                                    .onSurfaceVariant),
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
