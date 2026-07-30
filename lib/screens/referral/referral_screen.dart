import "package:firebase_auth/firebase_auth.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:qr_flutter/qr_flutter.dart";
import "package:share_plus/share_plus.dart";

import "package:prox/screens/monetization/business_paywall_screen.dart";
import "package:prox/services/points_service.dart";
import "package:prox/services/referral/referral_service.dart" as refsvc;

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  bool _creating = false;
  bool _allowInPersonQrPartyJoin = false;
  bool _loadingPartyToggle = true;

  String _buildLink({required String code, required String uid}) {
    return "https://prox-us.com/?code=$code&ref=$uid";
  }

  String _buildInPersonQrLink({required String code, required String uid}) {
    return "https://prox-us.com/?code=$code&ref=$uid&party=1&inperson=1";
  }

  @override
  void initState() {
    super.initState();
    _loadReferralPartyToggle();
  }

  Future<void> _loadReferralPartyToggle() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.trim().isEmpty) {
      if (!mounted) return;
      setState(() => _loadingPartyToggle = false);
      return;
    }

    final allowed = await refsvc.ReferralService.instance.getAllowInPersonQrPartyJoin(uid);
    if (!mounted) return;
    setState(() {
      _allowInPersonQrPartyJoin = allowed;
      _loadingPartyToggle = false;
    });
  }

  Future<void> _setReferralPartyToggle(String uid, bool value) async {
    setState(() {
      _loadingPartyToggle = true;
      _allowInPersonQrPartyJoin = value;
    });

    try {
      await refsvc.ReferralService.instance.setAllowInPersonQrPartyJoin(uid, value);
    } finally {
      if (!mounted) return;
      setState(() => _loadingPartyToggle = false);
    }
  }

  Future<void> _copy(String value, {String msg = "Copied"}) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _share(String value) async {
    try {
      await Share.share(value);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open share sheet")),
      );
    }
  }

  Future<void> _createCode(String uid) async {
    if (_creating) return;
    setState(() => _creating = true);

    final code = await refsvc.ReferralService.instance.createNewCode(
      uid: uid,
      remaining: 5,
      allowInPersonQrPartyJoin: _allowInPersonQrPartyJoin,
    );

    if (!mounted) return;
    setState(() => _creating = false);

    if (code == null || code.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not create invite code right now")),
      );
      return;
    }

    final link = _buildLink(code: code, uid: uid);
    await _copy(link, msg: "Referral link copied");
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (uid.isEmpty) {
      return const Scaffold(
        body: Center(child: Text("Sign in to view referrals")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Referrals")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          StreamBuilder<List<refsvc.ReferralCodeDoc>>(
            stream: refsvc.ReferralService.instance.streamMyCodes(uid),
            builder: (context, snapshot) {
              final codes = snapshot.data ?? const <refsvc.ReferralCodeDoc>[];
              final active = codes.where((c) => c.active).toList(growable: false);
              final code = active.isNotEmpty ? active.first.code : null;

              return Card(
                elevation: 0,
                color: cs.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: cs.outline.withValues(alpha: 0.25)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Share your invite",
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Payout unlock: +5 points when invitee completes their first 5 meetups.",
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _allowInPersonQrPartyJoin,
                        onChanged: _loadingPartyToggle
                            ? null
                            : (v) => _setReferralPartyToggle(uid, v),
                        title: const Text("Allow in-person QR referrals into my Party"),
                        subtitle: Text(
                          _allowInPersonQrPartyJoin
                              ? "ON: invitees who join via in-person QR can request direct Party pairing."
                              : "OFF: referrals will not trigger direct Party pairing.",
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (code == null)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _creating ? null : () => _createCode(uid),
                            icon: _creating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.add),
                            label: Text(_creating ? "Creating..." : "Create invite code"),
                          ),
                        )
                      else ...[
                        Text(
                          code,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _buildLink(code: code, uid: uid),
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "QR (in-person): ${_allowInPersonQrPartyJoin ? "Party join request enabled" : "Party join request disabled"}",
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _copy(
                                  _buildLink(code: code, uid: uid),
                                  msg: "Referral link copied",
                                ),
                                icon: const Icon(Icons.copy_all_outlined),
                                label: const Text("Copy"),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _share(
                                  "Join Prox with my invite: ${_buildLink(code: code, uid: uid)}",
                                ),
                                icon: const Icon(Icons.share),
                                label: const Text("Share"),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: QrImageView(
                              data: _allowInPersonQrPartyJoin
                                  ? _buildInPersonQrLink(code: code, uid: uid)
                                  : _buildLink(code: code, uid: uid),
                              size: 220,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          StreamBuilder<PointsMeta>(
            stream: PointsService.instance.watchMeta(uid),
            builder: (context, snap) {
              final meta = snap.data ?? PointsService.instance.peekMeta(uid);
              const int businessModeTarget = 50;
              final int left = (businessModeTarget - meta.currentPoints).clamp(0, 999999);

              return Card(
                elevation: 0,
                color: cs.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: cs.outline.withValues(alpha: 0.25)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Points snapshot",
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text("Current points: ${meta.currentPoints}"),
                      Text("Referral count: ${meta.referrals}"),
                      Text("Support sessions: ${meta.supportSessions}"),
                      Text("Points needed for Business Mode target (50): $left"),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outline.withValues(alpha: 0.25)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Quick actions",
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).pushNamed("/store"),
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                        label: const Text("Wallet"),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pushNamed("/store"),
                        icon: const Icon(Icons.shopping_bag_outlined),
                        label: const Text("Prox Store"),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const BusinessPaywallScreen(),
                              fullscreenDialog: true,
                            ),
                          );
                        },
                        icon: const Icon(Icons.storefront_outlined),
                        label: const Text("Business mode"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          StreamBuilder<List<refsvc.ReferralInviteDoc>>(
            stream: refsvc.ReferralService.instance.streamMyInvites(uid),
            builder: (context, snapshot) {
              final invites = snapshot.data ?? const <refsvc.ReferralInviteDoc>[];
              int verified = 0;
              int pending = 0;
              int joined = 0;

              for (final r in invites) {
                if (r.status == "verified") {
                  verified++;
                } else if (r.status == "pending") {
                  pending++;
                } else {
                  joined++;
                }
              }

              int privatePointsGenerated = 0;
              int privatePointsPotential = 0;
              int totalMeetupsByReferrals = 0;
              for (final r in invites) {
                final cappedMeetups = r.meetupsCompleted.clamp(0, 5);
                totalMeetupsByReferrals += cappedMeetups;
                privatePointsPotential += cappedMeetups;
                if (r.rewardCredited) privatePointsGenerated += 5;
              }

              return Card(
                elevation: 0,
                color: cs.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: cs.outline.withValues(alpha: 0.25)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Referral dashboard",
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          _StatChip(label: "Total", value: invites.length.toString()),
                          _StatChip(label: "Joined", value: joined.toString()),
                          _StatChip(label: "Pending", value: pending.toString()),
                          _StatChip(label: "Verified", value: verified.toString()),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Private referral totals",
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text("Meetups completed by referrals: $totalMeetupsByReferrals"),
                      Text("Prox points generated (credited): $privatePointsGenerated"),
                      Text("Potential points from current progress: $privatePointsPotential"),
                      const SizedBox(height: 12),
                      if (invites.isEmpty)
                        Text(
                          "No referrals yet. Share your code or QR to start.",
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        )
                      else
                        for (final invite in invites)
                          _InviteTile(invite: invite, referrerUid: uid),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
      ),
      child: Text(
        "$label: $value",
        style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  final refsvc.ReferralInviteDoc invite;
  final String referrerUid;

  const _InviteTile({required this.invite, required this.referrerUid});

  DateTime? _readLastActive(Map<String, dynamic> data) {
    final fields = <dynamic>[
      data["lastActiveAt"],
      data["lastSeenAt"],
      data["updatedAt"],
      data["presenceTs"],
    ];
    for (final v in fields) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
    }
    return null;
  }

  String _lastActiveLabel(DateTime? dt) {
    if (dt == null) return "Last active: unknown";
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return "Last active: just now";
    if (diff.inHours < 1) return "Last active: ${diff.inMinutes}m ago";
    if (diff.inDays < 1) return "Last active: ${diff.inHours}h ago";
    if (diff.inDays < 7) return "Last active: ${diff.inDays}d ago";
    return "Last active: ${dt.month}/${dt.day}/${dt.year}";
  }

  String _cooldownLabel(Duration left) {
    if (left <= Duration.zero) return "";
    if (left.inHours >= 1) {
      return "Try again in ${left.inHours}h ${left.inMinutes % 60}m";
    }
    return "Try again in ${left.inMinutes}m";
  }

  Future<void> _nudge(BuildContext context) async {
    final left = await refsvc.ReferralService.instance.reminderCooldownLeft(
      referrerUid: referrerUid,
      inviteeUid: invite.uid,
    );
    if (left > Duration.zero) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Reminder cooldown active. ${_cooldownLabel(left)}")),
      );
      return;
    }

    final text =
      "Quick Prox boost from your referrer: you're doing great. Keep your momentum by finishing your next meetup, and if you need help, open Support Mode in the app and we'll help you get unstuck fast.";
    try {
      await Share.share(text);
      await refsvc.ReferralService.instance.markReminderSent(
        referrerUid: referrerUid,
        inviteeUid: invite.uid,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open share options for nudge.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final int progress = invite.meetupsCompleted.clamp(0, 5);
    final int remaining = (5 - progress).clamp(0, 5);
    final bool unlocked = progress >= 5 || invite.rewardGranted;
    final String status = invite.status.isEmpty ? "joined" : invite.status;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection("users").doc(invite.uid).snapshots(),
      builder: (context, userSnap) {
        final userData = userSnap.data?.data() ?? const <String, dynamic>{};
        final lastActive = _readLastActive(userData);

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surface,
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
                      invite.uid,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(status, style: theme.textTheme.labelSmall),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                "Meetup progress: $progress/5 (completed meetups: ${invite.meetupsCompleted})",
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                _lastActiveLabel(lastActive),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: (progress / 5).clamp(0.0, 1.0)),
              const SizedBox(height: 6),
              Text(
                unlocked
                    ? (invite.rewardCredited ? "Reward credited: +5 points" : "Reward unlocked, credit pending sync")
                    : "$remaining more meetup${remaining == 1 ? "" : "s"} needed for +5 points",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: unlocked ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              FutureBuilder<Duration>(
                future: refsvc.ReferralService.instance.reminderCooldownLeft(
                  referrerUid: referrerUid,
                  inviteeUid: invite.uid,
                ),
                builder: (context, cooldownSnap) {
                  final left = cooldownSnap.data ?? Duration.zero;
                  final coolingDown = left > Duration.zero;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (coolingDown)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            "Reminder cooldown active. ${_cooldownLabel(left)}",
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: coolingDown ? null : () => _nudge(context),
                              icon: const Icon(Icons.campaign_outlined),
                              label: const Text("Nudge"),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).pushNamed("/support"),
                              icon: const Icon(Icons.support_agent_outlined),
                              label: const Text("Contact support"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}





