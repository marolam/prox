import "package:firebase_auth/firebase_auth.dart";
import "dart:async";
import "package:cloud_firestore/cloud_firestore.dart";
import "package:cloud_functions/cloud_functions.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:qr_flutter/qr_flutter.dart";
import "package:share_plus/share_plus.dart";

import "package:prox/screens/monetization/business_paywall_screen.dart";
import "package:prox/services/points_service.dart";
import "package:prox/services/referral/referral_service.dart" as refsvc;
import "package:prox/screens/review/growth_hub_screen.dart";
import "package:prox/services/in_person_referral_service.dart";
import "package:prox/widgets/referral_mentor_card.dart";

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  bool _allowInPersonQrPartyJoin = false;
  bool _loadingPartyToggle = true;
  String? _partyToggleError;
  bool _creatingPartyQr = false;
  InPersonReferralQr? _partyQr;
  Timer? _partyQrTimer;

  Future<void> _createInPersonQr() async {
    if (_creatingPartyQr) return;
    setState(() => _creatingPartyQr = true);
    try {
      final qr = await InPersonReferralService.createQr(
        addToParty: _allowInPersonQrPartyJoin,
      );
      if (!mounted) return;
      _partyQrTimer?.cancel();
      setState(() => _partyQr = qr);
      _partyQrTimer = Timer(qr.expiresAt.difference(DateTime.now()), () {
        if (mounted) setState(() => _partyQr = null);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _creatingPartyQr = false);
    }
  }

  @override
  void dispose() {
    _partyQrTimer?.cancel();
    super.dispose();
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

    setState(() {
      _loadingPartyToggle = true;
      _partyToggleError = null;
    });
    try {
      final allowed = await refsvc.ReferralService.instance
          .getAllowInPersonQrPartyJoin(uid);
      if (!mounted) return;
      setState(() => _allowInPersonQrPartyJoin = allowed);
    } catch (error) {
      if (mounted)
        setState(
          () => _partyToggleError =
              'Could not load your Party invite setting: $error',
        );
    } finally {
      if (mounted) setState(() => _loadingPartyToggle = false);
    }
  }

  Future<void> _setReferralPartyToggle(String uid, bool value) async {
    final previous = _allowInPersonQrPartyJoin;
    _partyQrTimer?.cancel();
    setState(() {
      _loadingPartyToggle = true;
      _allowInPersonQrPartyJoin = value;
      _partyQr = null;
    });

    try {
      await refsvc.ReferralService.instance.setAllowInPersonQrPartyJoin(
        uid,
        value,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _allowInPersonQrPartyJoin = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save your Party invite setting: $error'),
        ),
      );
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
          ReferralMentorCard(uid: uid),
          const GrowthReferralEntry(),
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
                    "Invite someone face to face",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Payout unlock: +5 points when invitee completes their first 5 meetups.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _allowInPersonQrPartyJoin,
                    onChanged: _loadingPartyToggle || _partyToggleError != null
                        ? null
                        : (v) => _setReferralPartyToggle(uid, v),
                    title: const Text(
                      "Add my referrals to Party after profile setup",
                    ),
                    subtitle: Text(
                      _allowInPersonQrPartyJoin
                          ? "ON: after in-person verification, consent and profile setup, your referral gets a direct mentor contact."
                          : "OFF: you are still their mentor, but referrals will not automatically add a Party contact.",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_partyToggleError != null) ...[
                    Text(_partyToggleError!),
                    TextButton(
                      onPressed: _loadReferralPartyToggle,
                      child: const Text('Retry invite setting'),
                    ),
                  ],
                  FilledButton.icon(
                    onPressed:
                        _creatingPartyQr ||
                            _loadingPartyToggle ||
                            _partyToggleError != null
                        ? null
                        : _createInPersonQr,
                    icon: const Icon(Icons.qr_code),
                    label: Text(
                      _creatingPartyQr
                          ? 'Creating...'
                          : _partyQr == null
                          ? 'Create in-person QR'
                          : 'Refresh in-person QR',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Both locations must verify that you are together. '
                    'After installing Prox, reopen this fresh QR link while you are still together. '
                    'Forwarded links and ordinary invite codes cannot unlock a new account.',
                  ),
                  if (_partyQr != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _copy(
                              _partyQr!.link,
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
                              "Open my Prox QR link while we are together: ${_partyQr!.link}",
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
                          data: _partyQr!.link,
                          size: 220,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          StreamBuilder<PointsMeta>(
            stream: PointsService.instance.watchMeta(uid),
            builder: (context, snap) {
              final meta = snap.data ?? PointsService.instance.peekMeta(uid);

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
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text("Current points: ${meta.currentPoints}"),
                      Text("Referral count: ${meta.referrals}"),
                      Text("Support sessions: ${meta.supportSessions}"),
                      Text(
                        "Business Mode access depends on your verified referrals and current plan. View its eligibility below.",
                      ),
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
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () =>
                            Navigator.of(context).pushNamed("/store"),
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                        label: const Text("Wallet"),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            Navigator.of(context).pushNamed("/store"),
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
              final invites =
                  snapshot.data ?? const <refsvc.ReferralInviteDoc>[];
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
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          _StatChip(
                            label: "Total",
                            value: invites.length.toString(),
                          ),
                          _StatChip(label: "Joined", value: joined.toString()),
                          _StatChip(
                            label: "Pending",
                            value: pending.toString(),
                          ),
                          _StatChip(
                            label: "Verified",
                            value: verified.toString(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Private referral totals",
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Meetups completed by referrals: $totalMeetupsByReferrals",
                      ),
                      Text(
                        "Prox points generated (credited): $privatePointsGenerated",
                      ),
                      Text(
                        "Potential points from current progress: $privatePointsPotential",
                      ),
                      const SizedBox(height: 12),
                      if (invites.isEmpty)
                        Text(
                          "No referrals yet. Share your code or QR to start.",
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
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
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  final refsvc.ReferralInviteDoc invite;
  final String referrerUid;

  const _InviteTile({required this.invite, required this.referrerUid});

  DateTime? _readProfileUpdatedAt(Map<String, dynamic> data) {
    final fields = <dynamic>[data["updatedAt"]];
    for (final v in fields) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
    }
    return null;
  }

  String _profileUpdatedLabel(DateTime? dt) {
    if (dt == null) return "Mentor progress not available yet";
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return "Mentor progress updated: just now";
    if (diff.inHours < 1)
      return "Mentor progress updated: ${diff.inMinutes}m ago";
    if (diff.inDays < 1) return "Mentor progress updated: ${diff.inHours}h ago";
    if (diff.inDays < 7) return "Mentor progress updated: ${diff.inDays}d ago";
    return "Mentor progress updated: ${dt.month}/${dt.day}/${dt.year}";
  }

  String _cooldownLabel(Duration left) {
    if (left <= Duration.zero) return "";
    if (left.inHours >= 1) {
      return "Try again in ${left.inHours}h ${left.inMinutes % 60}m";
    }
    return "Try again in ${left.inMinutes}m";
  }

  Future<void> _nudge(
    BuildContext context, {
    bool suggestSupport = false,
  }) async {
    try {
      await refsvc.ReferralService.instance.sendMentorReminder(
        referrerUid: referrerUid,
        inviteeUid: invite.uid,
        suggestSupport: suggestSupport,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Mentor reminder queued and saved in their Referrals screen.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is FirebaseFunctionsException
                ? error.message ??
                      'Could not send the reminder. Please try again.'
                : 'Could not send the reminder. Check your connection and account, then try again.',
          ),
        ),
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
      stream: FirebaseFirestore.instance
          .collection("users")
          .doc(referrerUid)
          .collection("mentorReferrals")
          .doc(invite.uid)
          .snapshots(),
      builder: (context, userSnap) {
        final userData = userSnap.data?.data() ?? const <String, dynamic>{};
        final profileUpdatedAt = _readProfileUpdatedAt(userData);

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
                      (userData['displayName'] as String?) ?? invite.uid,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(status, style: theme.textTheme.labelSmall),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Your referral / mentee',
                style: theme.textTheme.labelMedium,
              ),
              Text(
                userSnap.hasError
                    ? 'Mentor progress unavailable. Reopen this screen or contact support.'
                    : 'Profile: ${userData["profileComplete"] == true ? "complete" : "not completed yet"}'
                          ' · Conversation: ${userData["hasConversation"] == true ? "verified" : "not verified yet"}'
                          ' · Verified meetups: ${userData["meetupsCompleted"] ?? invite.meetupsCompleted}',
              ),
              if ((userData['growthRewardStatus'] as String? ?? '').isNotEmpty)
                Text(
                  'Invite reward: ${userData["growthRewardStatus"]}. Requires a completed meetup; a conversation alone does not pay.',
                ),
              const SizedBox(height: 4),
              Text(
                "Meetup progress: $progress/5 (completed meetups: ${invite.meetupsCompleted})",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _profileUpdatedLabel(profileUpdatedAt),
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
                    ? (invite.rewardCredited
                          ? "Reward credited: +5 points"
                          : "Reward unlocked, credit pending sync")
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
                  final reminderUnavailable =
                      cooldownSnap.hasError ||
                      cooldownSnap.connectionState != ConnectionState.done ||
                      userSnap.hasError;
                  final left = cooldownSnap.data ?? Duration.zero;
                  final coolingDown = left > Duration.zero;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (cooldownSnap.hasError)
                        const Text(
                          'Could not check reminder eligibility. Reopen referrals to retry.',
                        ),
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
                              onPressed: coolingDown || reminderUnavailable
                                  ? null
                                  : () => _nudge(context),
                              icon: const Icon(Icons.campaign_outlined),
                              label: const Text("Nudge"),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  Navigator.of(context).pushNamed("/support"),
                              icon: const Icon(Icons.support_agent_outlined),
                              label: const Text("Contact support"),
                            ),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: coolingDown || reminderUnavailable
                            ? null
                            : () => _nudge(context, suggestSupport: true),
                        icon: const Icon(Icons.support_agent_outlined),
                        label: const Text('Suggest support to this user'),
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
