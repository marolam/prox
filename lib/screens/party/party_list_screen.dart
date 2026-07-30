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

import "package:prox/screens/party/party_keyword_browser_screen.dart";
import "package:prox/screens/party/party_member_profile_screen.dart";
import "package:prox/screens/party/party_private_notes_screen.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/party_service.dart";
import "package:prox/services/user_profile_service.dart";

class PartyListScreen extends StatelessWidget {
  const PartyListScreen({super.key});

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
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                "See top 'want' and 'can provide' keywords across your party, then open message or meetup from each keyword.",
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PartyKeywordBrowserScreen(entries: entries),
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
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PartyPrivateNotesScreen(),
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

  void _openMember(BuildContext context, String otherUid) {
    final previous = ContextHelpService.instance.contextKey.value;
    ContextHelpService.instance.setContext("party:member_profile");
    // ignore: discarded_futures
    Navigator.of(context)
        .push(
      MaterialPageRoute<void>(
        builder: (_) => PartyMemberProfileScreen(otherUid: otherUid),
      ),
    )
        .then((_) {
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
        final Map<String, PartyMemberEntry> partyByUid = <String, PartyMemberEntry>{
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
                side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Party list unavailable",
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "We could not load Party members right now. Pull to refresh or reopen this tab.",
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection("profiles").limit(200).snapshots(),
          builder: (context, profilesSnap) {
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
            final Map<String, UserProfile> profileByUid = <String, UserProfile>{};
            for (final doc in profilesSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
              final uid = doc.id.trim();
              if (uid.isEmpty || uid == myUid) continue;
              profileByUid[uid] = UserProfile.fromMap(uid, doc.data());
            }

            final Set<String> referredByMeUids = <String>{};
            final referralDocs = myReferralsSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            for (final doc in referralDocs) {
              final id = doc.id.trim();
              if (id.isNotEmpty) referredByMeUids.add(id);
              final uid = (doc.data()["uid"] ?? "").toString().trim();
              if (uid.isNotEmpty) referredByMeUids.add(uid);
            }

            final Set<String> referredMeUids = <String>{};
            final referredByDocs = referredBySnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            for (final doc in referredByDocs) {
              final referrerUid = doc.reference.parent.parent?.id.trim() ?? "";
              if (referrerUid.isNotEmpty && referrerUid != myUid) {
                referredMeUids.add(referrerUid);
              }
            }

            final Set<String> visibleUidSet = <String>{
              ...partyByUid.keys,
              ...profileByUid.keys,
            };
            final List<String> visibleUids = visibleUidSet.toList(growable: true)
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

                final an = (profileByUid[a]?.displayName ?? "").trim().toLowerCase();
                final bn = (profileByUid[b]?.displayName ?? "").trim().toLowerCase();
                if (an.isNotEmpty && bn.isNotEmpty) {
                  final cmp = an.compareTo(bn);
                  if (cmp != 0) return cmp;
                }
                if (an.isNotEmpty && bn.isEmpty) return -1;
                if (an.isEmpty && bn.isNotEmpty) return 1;
                return a.compareTo(b);
              });

            if (visibleUids.isEmpty) {
              final bool waiting = snap.connectionState == ConnectionState.waiting ||
                  profilesSnap.connectionState == ConnectionState.waiting;
              return Column(
                children: [
                  _keywordEntryCard(context, theme: theme, cs: cs, entries: entries),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                    child: Card(
                      elevation: 0,
                      color: cs.surfaceContainerHighest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          waiting
                              ? "Loading members..."
                              : "No members found yet.",
                          style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            return Column(
              children: [
                _keywordEntryCard(context, theme: theme, cs: cs, entries: entries),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 12),
                  itemCount: visibleUids.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (context, i) {
                    final uid = visibleUids[i];
                    final e = partyByUid[uid];
                    final p = profileByUid[uid];
                    final inParty = e != null;
                    final referredByMe = referredByMeUids.contains(uid);
                    final referredMe = referredMeUids.contains(uid);
                    final hasReferralRelationship = referredByMe || referredMe;

                    final String name = (p?.displayName ?? "").trim().isNotEmpty
                        ? p!.displayName!.trim()
                        : _uidFallback(uid);
                    final String photoUrl = (p?.photoUrl ?? "").trim();

                    final Color cardColor = hasReferralRelationship
                        ? cs.tertiaryContainer.withValues(alpha: 0.5)
                        : cs.surfaceContainerHighest;
                    final Color borderColor = hasReferralRelationship
                        ? cs.tertiary.withValues(alpha: 0.55)
                        : cs.outlineVariant.withValues(alpha: 0.55);
                    final Color nameColor = hasReferralRelationship
                        ? cs.onTertiaryContainer
                        : (theme.textTheme.titleSmall?.color ?? cs.onSurface);

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                            PartyService.instance.reconcileMutual(uid);
                          }
                          _openMember(context, uid);
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          child: Row(
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
                                  Row(
                                    children: [
                                      Text(
                                        name,
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: nameColor,
                                        ),
                                      ),
                                      if (referredMe) ...[
                                        const SizedBox(width: 8),
                                        _RelationshipPill(
                                          icon: Icons.person_search_outlined,
                                          label: "Referred You",
                                          bg: cs.secondaryContainer,
                                          fg: cs.onSecondaryContainer,
                                          border: cs.secondary.withValues(alpha: 0.45),
                                        ),
                                      ],
                                      if (referredByMe) ...[
                                        const SizedBox(width: 8),
                                        _RelationshipPill(
                                          icon: Icons.campaign_outlined,
                                          label: "Your Referral",
                                          bg: cs.primaryContainer,
                                          fg: cs.onPrimaryContainer,
                                          border: cs.primary.withValues(alpha: 0.45),
                                        ),
                                      ],
                                      if (e?.mutual == true) ...[
                                        const SizedBox(width: 8),
                                        const _MutualPill(),
                                      ],
                                      if (inParty && e.mutual != true) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: cs.primaryContainer,
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            "In Party",
                                            style: theme.textTheme.labelSmall?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: cs.onPrimaryContainer,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (e?.since != null)
                                    Text(
                                      "Added: ${_friendlyDate(e!.since!)}",
                                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                    ),
                                ],
                              ),
                              const Spacer(),
                              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                              IconButton(
                                tooltip: inParty ? "Remove" : "Add to Party",
                                icon: Icon(inParty ? Icons.person_remove_outlined : Icons.person_add_alt_1_outlined),
                                onPressed: () async {
                                  if (inParty) {
                                    final bool? ok = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text("Remove from Party?"),
                                        content: const Text("Are you sure? You can add them again later."),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Remove")),
                                        ],
                                      ),
                                    );
                                    if (ok != true) return;

                                    await PartyService.instance.removeFromParty(uid);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text("Removed from Party")),
                                      );
                                    }
                                    return;
                                  }

                                  await PartyService.instance.addToParty(
                                    uid,
                                    source: "partyDirectoryAdd",
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("Added to Party")),
                                    );
                                  }
                                },
                              ),
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


