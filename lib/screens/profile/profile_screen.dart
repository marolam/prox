import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/screens/profile/profile_edit_screen.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/mode_unlock_service.dart";
import "package:prox/services/monetization_entry_service.dart";
import "package:prox/services/monetization_service.dart";
import "package:prox/services/points_service.dart";
import "package:prox/services/progression_service.dart";
import "package:prox/services/user_profile_service.dart";
import "package:prox/services/user_settings_service.dart";
import "package:prox/widgets/profile_status_row.dart";
import "package:prox/widgets/prox_trust_bar.dart";

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _openEdit(BuildContext context) async {
    final previous = ContextHelpService.instance.contextKey.value;
    ContextHelpService.instance.setContext("profile:edit");
    final nav = Navigator.of(context);
    final res = await nav.push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const ProfileEditScreen(fromOnboarding: false),
      ),
    );
    ContextHelpService.instance.setContext(previous);

    if (res == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile updated.")),
      );
    }
  }

  Future<void> _showBusinessSetupIntro(BuildContext context) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
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
              children: [
                Row(
                  children: [
                    Icon(Icons.work_outline, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Business Mode setup",
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Business Mode changes how you show up on Prox:",
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    " You'll be discoverable as a provider (optional)\n"
                    " People can filter to Business-only users\n"
                    " You can set availability (Immediate / within X minutes)\n"
                    " Reliability matters more (meet  rate  trust)\n\n"
                    "Tip: After switching, go to Discovery settings and try the Business-only filter.",
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.25),
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

  Future<void> _switchToParty(BuildContext context) async {
    final prev = UserSettingsService.instance.current.uxMode;
    if (prev == AppUxMode.party) return;

    UserSettingsService.instance.setUxMode(AppUxMode.party);

    if (!UserSettingsService.instance.current.hasSeenModeExplainer && context.mounted) {
      UserSettingsService.instance.markModeExplainerSeen();
      // Keep it light here; Settings screen already has deeper explainer via ModeSwitchCard.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Switched to Personal Mode.")),
      );
    }
  }

  Future<void> _switchToBusiness(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Sign in to activate Business Mode.")),
        );
      }
      return;
    }

    final unlock = await ModeUnlockService.instance.loadForUser(uid);
    final earned = unlock?.canUseBusiness ?? false;
    if (!earned) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Business Mode is locked. Complete progression requirements first."),
          ),
        );
      }
      return;
    }

    final paid = await MonetizationService.instance.isBusinessUnlocked(uid);
    if (!paid) {
      if (context.mounted) {
        await MonetizationEntryService.instance.openBusinessPaywall(context);
      }
      return;
    }

    UserSettingsService.instance.setUxMode(AppUxMode.business);

    if (!UserSettingsService.instance.current.hasSeenModeExplainer) {
      UserSettingsService.instance.markModeExplainerSeen();
      if (context.mounted) {
        await _showBusinessSetupIntro(context);
      }
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Switched to Business Mode.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile"),
        actions: [
          IconButton(
            tooltip: "Edit profile",
            icon: const Icon(Icons.edit),
            onPressed: () => _openEdit(context),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: UserSettingsService.instance.watch(),
        builder: (context, _) {
          final settings = UserSettingsService.instance.current;
          final bool isBusinessMode = settings.uxMode == AppUxMode.business;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              // Big obvious mode switch CTA
              Card(
                elevation: 0,
                color: cs.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: cs.outline.withValues(alpha: 0.25)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(
                        isBusinessMode ? Icons.work_outline : Icons.person_outline,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isBusinessMode ? "Business Mode" : "Personal Mode",
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isBusinessMode
                                  ? "Outcome-first: availability + clearer actions."
                                  : "Discovery-first: relaxed prompts and social flow.",
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: () => isBusinessMode ? _switchToParty(context) : _switchToBusiness(context),
                        child: Text(isBusinessMode ? "Switch to Personal" : "Switch to Business"),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Primary, obvious entry point (in addition to AppBar icon).
              Card(
                elevation: 0,
                color: cs.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: cs.outline.withValues(alpha: 0.25)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Your profile",
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Update name, selfie, headline, keywords, and Business availability.",
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: () => _openEdit(context),
                        icon: const Icon(Icons.edit),
                        label: const Text("Edit"),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              if (uid.isNotEmpty) ...[
                Card(
                  elevation: 0,
                  color: cs.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: cs.outline.withValues(alpha: 0.25)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: FutureBuilder<ProgressionSnapshot?>(
                      future: ProgressionService.instance.loadForUser(uid),
                      builder: (context, snap) {
                        final progression = snap.data;

                        return StreamBuilder<PointsMeta>(
                          stream: PointsService.instance.watchMeta(uid),
                          builder: (context, pointsSnap) {
                            final points = pointsSnap.data ?? PointsService.instance.peekMeta(uid);
                            final int level = progression?.level ??
                                ProgressionService.instance.levelFromTotalPoints(points.totalPoints);
                            final int toNext =
                                ProgressionService.instance.pointsToNextLevel(points.totalPoints);
                            final int ageDays = progression?.accountAgeDays ?? 0;

                            ProxFeatureUnlock? nextFeature;
                            for (final feature in ProxFeatureUnlock.values) {
                              final unlocked = progression?.has(feature) ?? false;
                              if (!unlocked) {
                                nextFeature = feature;
                                break;
                              }
                            }

                            final String nextLabel = nextFeature == null
                                ? "All core features unlocked"
                                : ProgressionService.instance.requirementLabel(nextFeature);
                            final String nextReason =
                                (nextFeature == null || progression == null)
                                    ? ""
                                    : ProgressionService.instance.lockedReason(
                                        feature: nextFeature,
                                        snapshot: progression,
                                      );

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Progression",
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Level $level  Total points: ${points.totalPoints}",
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Next level in $toNext points  Account age: ${ageDays}d",
                                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cs.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Next unlock",
                                        style: theme.textTheme.labelMedium?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        nextLabel,
                                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                      ),
                                      if (nextReason.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          nextReason,
                                          style: theme.textTheme.bodySmall?.copyWith(color: cs.primary),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (uid.isNotEmpty) ...[
                Card(
                  elevation: 0,
                  color: cs.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: cs.outline.withValues(alpha: 0.25)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: ProfileStatusRow(uid: uid),
                  ),
                ),
                const SizedBox(height: 12),
              ],

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
                        "Trust",
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      const ProxTrustBar(),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              if (uid.isNotEmpty) ...[
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                "Introduced",
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            Switch(
                              value: settings.referralSignalEnabled,
                              onChanged: (v) => UserSettingsService.instance.setReferralSignalEnabled(v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Referrals are a vouch, not a lock. Toggle only affects what you see.",
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 10),
                        StreamBuilder<UserProfile?>(
                          stream: UserProfileService.instance.watchProfile(uid),
                          builder: (context, snap) {
                            final me = snap.data;
                            final refUid = (me?.referrerUid ?? "").trim();
                            if (refUid.isEmpty || !settings.referralSignalEnabled) {
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cs.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.auto_awesome, color: cs.onSurfaceVariant, size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        settings.referralSignalEnabled ? "No introduction attached yet." : "Referral signal hidden.",
                                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return FutureBuilder<UserProfile?>(
                              future: UserProfileService.instance.getProfileOnce(refUid),
                              builder: (context, refSnap) {
                                final ref = refSnap.data;
                                final name = (ref?.displayName ?? "a friend").trim();

                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cs.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.auto_awesome, color: cs.primary, size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Introduced by $name",
                                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "Warm intros help early trust and reduce spam.",
                                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.2),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

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
                        "Business Mode access",
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Earn unlock through trust + activity, then activate with payment. "
                        "Once eligible, Prox always shows a reachable activation path.",
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),

                      if (uid.isEmpty) ...[
                        Text(
                          "Status: sign in to view your unlock progress.",
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ] else ...[
                        FutureBuilder<ModeUnlockState?>(
                          future: ModeUnlockService.instance.loadForUser(uid),
                          builder: (context, unlockSnap) {
                            final unlock = unlockSnap.data;
                            final earned = unlock?.canUseBusiness ?? false;
                            final referrals = unlock?.verifiedReferrals ?? 0;
                            final meetups = unlock?.completedMeetups ?? 0;
                            final needed = unlock?.neededForBusiness ?? 0;

                            return FutureBuilder<bool>(
                              future: MonetizationService.instance.isBusinessUnlocked(uid),
                              builder: (context, paidSnap) {
                                final paid = paidSnap.data ?? false;

                                final String status;
                                if (paid) {
                                  status = "Status: active access (toggle in Profile/Settings)";
                                } else if (earned) {
                                  status = "Status: unlocked to buy (activation available)";
                                } else {
                                  status = "Status: locked (earn unlock first)";
                                }

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      status,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: cs.surface,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
                                      ),
                                      child: Text(
                                        "Unlock snapshot:\n"
                                        " Referrals: $referrals\n"
                                        " Meetups: $meetups\n"
                                        "${needed > 0 ? " Steps remaining (combined): $needed" : " Eligible: Yes"}",
                                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.25),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        icon: const Icon(Icons.payments_outlined),
                                        label: Text(paid ? "Manage Business" : "Open Business paywall"),
                                        onPressed: () => MonetizationEntryService.instance.openBusinessPaywall(context),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}