import "package:firebase_auth/firebase_auth.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter/material.dart";

import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/points_service.dart";
import "package:prox/services/prox_points/prox_points_events_service.dart";
import "package:prox/services/prox_points/prox_points_service.dart";
import "package:prox/services/support_mode_service.dart";
import "package:prox/screens/settings/account/buy_points_screen.dart";
import "package:prox/screens/store/prox_store_screen.dart";
import "package:prox/screens/settings/tester_progress_screen.dart";
import "package:prox/release/rollout_gate_service.dart";
import "package:prox/services/monetization_entry_service.dart";
import "package:prox/services/monetization_service.dart";

class ProxPointsScreen extends StatefulWidget {
  final String? debugUidOverride;
  final Future<bool> Function(String uid)? walletUnlockedOverride;
  final Future<void> Function(BuildContext context)? openBillingActivationOverride;
  final WidgetBuilder? unlockedBodyOverride;

  const ProxPointsScreen({
    super.key,
    this.debugUidOverride,
    this.walletUnlockedOverride,
    this.openBillingActivationOverride,
    this.unlockedBodyOverride,
  });

  @override
  State<ProxPointsScreen> createState() => _ProxPointsScreenState();
}

class _ProxPointsScreenState extends State<ProxPointsScreen> {
  String _resolveUid() {
    final override = widget.debugUidOverride;
    if (override != null) return override;
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? "";
    } catch (_) {
      return "";
    }
  }

  Future<void> _pushWithHelpContext({
    required String contextKey,
    required Widget page,
  }) async {
    final previous = ContextHelpService.instance.contextKey.value;
    ContextHelpService.instance.setContext(contextKey);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    ContextHelpService.instance.setContext(previous);
  }

  Future<void> _grantTestPoints(String uid, int amount) async {
    if (uid.trim().isEmpty || amount <= 0) return;

    try {
      final docRef = FirebaseFirestore.instance
          .collection("users")
          .doc(uid)
          .collection("meta")
          .doc("points");

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        final data = snap.data() ?? const <String, dynamic>{};

        final current = (data["currentPoints"] as num?)?.toInt() ?? 0;
        final total = (data["totalPoints"] as num?)?.toInt() ?? 0;

        tx.set(
          docRef,
          <String, Object?>{
            "currentPoints": current + amount,
            "totalPoints": total + amount,
            "lastActivity": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        final eventRef = docRef.collection("events").doc();
        tx.set(
          eventRef,
          <String, Object?>{
            "eventId": eventRef.id,
            "timestamp": FieldValue.serverTimestamp(),
            "reason": "Tester seed points",
            "category": "tester_seed",
            "amount": amount,
            "contextType": "debug",
          },
        );
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final message = (e.code == "permission-denied")
          ? "Firestore permission denied while seeding points."
          : "Seed failed: ${e.message ?? e.code}";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Added $amount points to this account.")),
    );
  }

  Future<void> _openSeedSheet(String uid) async {
    final amounts = <int>[100, 500, 2000, 10000];

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Tester seed points",
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  "Adds points to the signed-in account for purchase testing.",
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: amounts
                      .map(
                        (amount) => FilledButton.tonal(
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            await _grantTestPoints(uid, amount);
                          },
                          child: Text("+$amount"),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _unlockEverythingForDev(String uid) async {
    if (uid.trim().isEmpty) return;

    try {
      final fs = FirebaseFirestore.instance;
      final now = DateTime.now();

      final userRef = fs.collection("users").doc(uid);
      final profileRef = fs.collection("profiles").doc(uid);
      final pointsRef = userRef.collection("meta").doc("points");
      final progressionRef = userRef.collection("meta").doc("progression");
      final entitlementRef = userRef.collection("billing").doc("entitlements");
      final businessProfileRef = userRef.collection("business").doc("profile");
      final businessSubRef = userRef.collection("business").doc("subscription");

      final batch = fs.batch();
        final bool businessWriteEnabled =
          RolloutGateService.instance.isBusinessModeWriteEnabled;

      batch.set(userRef, <String, Object?>{
        "businessEnabled": true,
        "isBusiness": true,
        "joinedAt": Timestamp.fromDate(now.subtract(const Duration(days: 45))),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(profileRef, <String, Object?>{
        "businessEnabled": true,
        "isBusiness": true,
        "joinedAt": Timestamp.fromDate(now.subtract(const Duration(days: 45))),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(pointsRef, <String, Object?>{
        "totalPoints": 10000,
        "currentPoints": 10000,
        "completedMeetups": 30,
        "onTimeArrivals": 30,
        "fiveStarMeetups": 30,
        "referrals": 30,
        "supportSessions": 30,
        "trustPercent": 99.0,
        "trustScore": 99.0,
        "level": 10,
        "lastActivity": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(progressionRef, <String, Object?>{
        "level": 10,
        "totalPoints": 10000,
        "accountAgeDays": 45,
        "features": <String, Object?>{
          "referrals": true,
          "supportMode": true,
          "supportTechnician": true,
          "treeMode": true,
          "publicMode": true,
          "businessMode": true,
        },
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(entitlementRef, <String, Object?>{
        "businessPurchased": true,
        "businessSubscriptionActive": true,
        "businessModeActive": businessWriteEnabled,
        "lastSku": "dev_unlock_all",
        "subscriptionStartedAt": FieldValue.serverTimestamp(),
        "subscriptionRenewsAt": Timestamp.fromDate(now.add(const Duration(days: 3650))),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(businessProfileRef, <String, Object?>{
        "uid": uid,
        "businessName": "Dev Unlocked Business",
        "businessCategory": "Tech",
        "businessDescription": "Auto-unlocked for tester/dev account.",
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(businessSubRef, <String, Object?>{
        "uid": uid,
        "tier": "business",
        "active": true,
        "autoRenew": true,
        "renewalDate": Timestamp.fromDate(now.add(const Duration(days: 3650))),
        "createdAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      for (int i = 0; i < 6; i++) {
        final ref = userRef.collection("referrals").doc("dev_verified_$i");
        batch.set(ref, <String, Object?>{
          "status": "verified",
          "createdAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
          "source": "dev_unlock_all",
        }, SetOptions(merge: true));
      }

      await batch.commit();

      await SupportModeService.instance.acceptTerms();
      await SupportModeService.instance.setEnabled(true);

      await PointsService.instance.refreshMeta(uid);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Dev unlock applied: trust, progression, business, and referrals maxed.")),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final msg = (e.code == "permission-denied")
          ? "Dev unlock failed: Firestore permission denied."
          : "Dev unlock failed: ${e.message ?? e.code}";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Dev unlock failed: $e")),
      );
    }
  }

  Future<void> _openSpendingPreferences(BuildContext context, String uid) async {
    final docRef = FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .collection("settings")
        .doc("monetization");

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: docRef.snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data() ?? const <String, dynamic>{};
            final preferPointsFirst = (data["preferPointsFirst"] as bool?) ?? true;

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Spending preferences",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    value: preferPointsFirst,
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Prefer points first"),
                    subtitle: const Text("When enabled, Prox uses your points for eligible purchases before other billing paths."),
                    onChanged: (value) async {
                      await docRef.set(
                        {
                          "preferPointsFirst": value,
                          "updatedAt": FieldValue.serverTimestamp(),
                        },
                        SetOptions(merge: true),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  IconData _kindIcon(String kind) {
    if (kind == "bug_report") return Icons.bug_report_outlined;
    if (kind.startsWith("referral")) return Icons.share_outlined;
    if (kind == "meetup_rated") return Icons.star_outline;
    if (kind == "cosmetic_unlocked") return Icons.palette_outlined;
    return Icons.stars_outlined;
  }

  Widget _lockedWalletBody(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outline.withValues(alpha: 0.24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Wallet locked until Business activation",
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Confirm Business activation in billing first to unlock wallet and store surfaces.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final open = widget.openBillingActivationOverride;
                    if (open != null) {
                      await open(context);
                      return;
                    }
                    await MonetizationEntryService.instance.openBusinessPaywall(
                      context,
                    );
                  },
                  icon: const Icon(Icons.lock_open_outlined),
                  label: const Text("Open billing activation"),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = _resolveUid();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Prox Points"),
        actions: [
          if (uid.trim().isNotEmpty)
            IconButton(
              tooltip: "Tester seed points",
              icon: const Icon(Icons.bolt_outlined),
              onPressed: () => _openSeedSheet(uid),
            ),
        ],
      ),
      body: uid.trim().isEmpty
          ? Center(
              child: Text(
                "Sign in to view your points.",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          : FutureBuilder<bool>(
              future: widget.walletUnlockedOverride != null
                  ? widget.walletUnlockedOverride!(uid)
                  : MonetizationService.instance.isBusinessWalletUnlocked(uid),
              builder: (context, walletUnlockSnap) {
                if (walletUnlockSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (walletUnlockSnap.data != true) {
                  return _lockedWalletBody(context);
                }

                if (widget.unlockedBodyOverride != null) {
                  return widget.unlockedBodyOverride!(context);
                }

                return StreamBuilder<ProxPointsSnapshot>(
                  stream: ProxPointsService.instance.streamMySnapshot(),
                  builder: (context, snap) {
                    final p = snap.data ?? ProxPointsSnapshot.empty;

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                    Card(
                      elevation: 0,
                      color: cs.surfaceContainerHighest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: cs.outline.withValues(alpha: 0.25)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.10),
                                shape: BoxShape.circle,
                                border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
                              ),
                              child: Icon(Icons.stars, color: cs.primary),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "${p.balance} Prox Points",
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Lifetime earned: ${p.lifetime}",
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Text(
                      "How points work",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Points are earned through helpful actions (bug reports, referrals, stories). "
                      "Cosmetics and perks may be unlocked with points, but cosmetics never fake trust.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),

                    const SizedBox(height: 16),

                    Text(
                      "Recent activity",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),

                    StreamBuilder<List<ProxPointEvent>>(
                      stream: ProxPointsEventsService.instance.watch(),
                      builder: (context, esnap) {
                        final events = esnap.data ?? const <ProxPointEvent>[];
                        if (events.isEmpty) {
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
                            ),
                            child: Text(
                              "No activity yet. Bug reports, referrals, and ratings will show up here.",
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          );
                        }

                        final top = events.take(8).toList(growable: false);

                        return Card(
                          elevation: 0,
                          color: cs.surfaceContainerHighest,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: cs.outline.withValues(alpha: 0.25)),
                          ),
                          child: Column(
                            children: [
                              for (int i = 0; i < top.length; i++) ...[
                                ListTile(
                                  leading: Icon(_kindIcon(top[i].kind)),
                                  title: Text(top[i].title),
                                  subtitle: Text(
                                    top[i].meta == null || top[i].meta!.isEmpty
                                        ? top[i].at.toLocal().toString()
                                        : "${top[i].at.toLocal()}  ${top[i].meta}",
                                  ),
                                  trailing: top[i].delta == 0
                                      ? null
                                      : Text(
                                          top[i].delta > 0 ? "+${top[i].delta}" : "${top[i].delta}",
                                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                                color: top[i].delta > 0 ? cs.primary : cs.error,
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                ),
                                if (i != top.length - 1) const Divider(height: 1),
                              ],
                            ],
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
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.receipt_long_outlined),
                            title: const Text("View tester progress"),
                            subtitle: const Text("Trust, completed meetups, and points summary."),
                            onTap: () => _pushWithHelpContext(
                              contextKey: "points:tester_progress",
                              page: const TesterProgressScreen(),
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.bolt_outlined),
                            title: const Text("Tester: Seed points"),
                            subtitle: const Text("Add test points for purchase flow validation."),
                            onTap: () => _openSeedSheet(uid),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.verified_user_outlined),
                            title: const Text("Dev: Unlock everything"),
                            subtitle: const Text("Max trust/points and clear feature/service requirements."),
                            onTap: () => _unlockEverythingForDev(uid),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.shopping_bag_outlined),
                            title: const Text("Buy points"),
                            subtitle: const Text("Top up your points balance."),
                            onTap: () => _pushWithHelpContext(
                              contextKey: "points:buy_points",
                              page: const BuyPointsScreen(),
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.discount_outlined),
                            title: const Text("Spending preferences"),
                            subtitle: const Text("Prefer points when it makes things cheaper."),
                            onTap: () => _openSpendingPreferences(context, uid),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.local_offer_outlined),
                            title: const Text("Deals & featured discounts"),
                            subtitle: const Text("Rotating discounts for points users."),
                            onTap: () => _pushWithHelpContext(
                              contextKey: "points:featured_deals",
                              page: const ProxStoreScreen(),
                            ),
                          ),
                        ],
                      ),
                    ),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }
}
