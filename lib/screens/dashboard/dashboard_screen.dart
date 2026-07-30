import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prox/app_router.dart';
import 'package:prox/models/dashboard_announcement.dart';
import 'package:prox/models/dashboard_metrics.dart';
import 'package:prox/screens/admin/creator_panel_screen.dart';
import 'package:prox/screens/services/points_service.dart';
import 'package:prox/screens/services/party_service.dart';
import 'package:prox/services/dashboard_announcements_service.dart';
import 'package:prox/services/business_mode/business_mode_eligibility.dart';
import 'package:prox/services/dashboard_metrics_service.dart';
import 'package:prox/services/ui_telemetry_service.dart';
import 'package:prox/widgets/store_locked_sheet.dart';
import 'package:prox/widgets/business_mode_gate.dart';
import 'package:prox/widgets/tester_badge.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static String _eventForRoute(String r) {
    if (r == "/store") return "store_open";
    if (r == "/support") return "support_open";
    if (r == "/referrals") return "referrals_open";
    if (r == "/account") return "account_open";
    if (r == "/policy") return "policy_open";
    if (r == AppRouter.testerMission) return "tester_mission_open";
    if (r == AppRouter.testerInsight) return "tester_insight_open";
    return "route_open";
  }

  static double _ratio(num value, num target) {
    if (target <= 0) return 0.0;
    final r = value / target;
    if (r < 0) return 0.0;
    if (r > 1) return 1.0;
    return r.toDouble();
  }

  static String _fmtInt(int value) {
    final s = value.toString();
    return s.replaceAllMapped(RegExp(r"\B(?=(\d{3})+(?!\d))"), (_) => ",");
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.trim().isEmpty) {
      return const Scaffold(body: Center(child: Text("Not signed in")));
    }

    Widget card({required Widget child}) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
          ),
          child: child,
        );

    Widget sectionTitle(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            t,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        );

    Widget pill(String t, {IconData? i}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (i != null) ...[
                Icon(i, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
              ],
              Text(
                t,
                style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        );

    final fallbackAnnouncements = const <DashboardAnnouncement>[
      DashboardAnnouncement(
        id: 'fallback',
        title: 'Platform layer live',
        body: 'Dashboard, Store shell, Support hub, and Referrals are available for testers.',
        active: true,
        pinned: false,
        broadcast: false,
        audience: 'all',
        createdAt: null,
        expiresAt: null,
      ),
    ];

    final fallbackTop = const [
      KeywordMetric(keyword: "flat tire help", count: 12),
      KeywordMetric(keyword: "ride share", count: 11),
      KeywordMetric(keyword: "moving help", count: 9),
      KeywordMetric(keyword: "phone charger", count: 8),
    ];

    final fallbackTrending = const [
      KeywordMetric(keyword: "bike repair", count: 0, delta: 6),
      KeywordMetric(keyword: "delivery pickup", count: 0, delta: 5),
      KeywordMetric(keyword: "dog walking", count: 0, delta: 4),
    ];

    void go(String r) {
      final ev = _eventForRoute(r);
      UiTelemetryService.instance.log(ev, meta: {"route": r, "source": "dashboard"});
      Navigator.of(context).pushNamed(r);
    }

    Future<void> openBusinessItem({
      required String sku,
      required bool businessUnlocked,
    }) async {
      UiTelemetryService.instance.log("dashboard_business_item_tap", meta: {"sku": sku});

      if (businessUnlocked) {
        go("/store");
        return;
      }

      await StoreLockedSheet.show(
        context,
        title: "Locked: Business Mode required",
        body:
            "This item is reserved for Business Mode.\n\n"
            "Business Mode is earned through trust, reliability, and meetups. Open Account & Billing to see your progress.",
        onGoToAccount: () => go("/account"),
      );
    }

    Widget progressRow({
      required String label,
      required String valueText,
      required double ratio,
      required IconData icon,
    }) {
      return Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                    Text(valueText, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: ratio,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(999),
                ),
              ],
            ),
          ),
        ],
      );
    }

    Widget metricChip({required String label, required String value, IconData? icon}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: cs.primary),
              const SizedBox(width: 8),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      );
    }

    Widget keywordChip({required String label, String? meta, IconData? icon}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outline.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: cs.primary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (meta != null && meta.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                meta,
                style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      );
    }

    Widget metricsSection() {
      return StreamBuilder<DashboardMetrics?>(
        stream: DashboardMetricsService.instance.watchMetrics(),
        builder: (context, snap) {
          final metrics = snap.data;
          final top = metrics?.topKeywords.isNotEmpty == true ? metrics!.topKeywords : fallbackTop;
          final trending = metrics?.trendingKeywords.isNotEmpty == true ? metrics!.trendingKeywords : fallbackTrending;
          final geofenceCovered = metrics?.geofenceUsersCovered ?? 0;
          final geofenceRatio = _ratio(
            metrics?.geofenceCoverageRatio ?? 0.0,
            1.0,
          );
          final totalUsersForCoverage = metrics?.totalUsers ?? 0;
          final totalPointsPaidOut = metrics?.totalPointsPaidOut ?? 0;
          final referralPointsPaidOut = metrics?.totalReferralPointsPaidOut ?? 0;
          final supportPointsPaidOut = metrics?.totalSupportPointsPaidOut ?? 0;
          final totalBusinessUsers = metrics?.totalBusinessModeUsers ?? 0;
          final newBusinessUsersToday = metrics?.newBusinessModeUsersToday ?? 0;

          return card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sectionTitle("Network pulse"),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    metricChip(
                      label: "Total users",
                      value: metrics != null ? _fmtInt(metrics.totalUsers) : "-",
                      icon: Icons.groups_outlined,
                    ),
                    metricChip(
                      label: "New today",
                      value: metrics != null ? _fmtInt(metrics.newUsersToday) : "-",
                      icon: Icons.trending_up,
                    ),
                    metricChip(
                      label: "Total points paid out",
                      value: _fmtInt(totalPointsPaidOut),
                      icon: Icons.card_giftcard_outlined,
                    ),
                    metricChip(
                      label: "Total Business Mode users",
                      value: _fmtInt(totalBusinessUsers),
                      icon: Icons.storefront_outlined,
                    ),
                    metricChip(
                      label: "New Business Mode users today",
                      value: _fmtInt(newBusinessUsersToday),
                      icon: Icons.today_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                progressRow(
                  label: "Geofence coverage",
                  valueText: "$geofenceCovered / $totalUsersForCoverage users",
                  ratio: geofenceRatio,
                  icon: Icons.location_on_outlined,
                ),
                const SizedBox(height: 10),
                Text(
                  "Points paid out from referrals and support tickets: ${_fmtInt(referralPointsPaidOut)} referral + ${_fmtInt(supportPointsPaidOut)} support.",
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Text(
                  "Grow the community by referring friends or helping in support. You can cover Business Mode with Prox Points instead of paying out-of-pocket.",
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                Text(
                  "Trending keywords",
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: trending
                      .map(
                        (k) => keywordChip(
                          label: k.keyword,
                          meta: k.delta != null ? "+${k.delta}" : null,
                          icon: Icons.arrow_upward,
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 12),
                Text(
                  "Top keywords",
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: top
                      .map(
                        (k) => keywordChip(
                          label: k.keyword,
                          meta: k.count.toString(),
                          icon: Icons.local_fire_department_outlined,
                        ),
                      )
                      .toList(growable: false),
                ),
                if (metrics?.updatedAt != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    "Updated ${metrics!.updatedAt!.toLocal().toString().substring(0, 16)}",
                    style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          );
        },
      );
    }

    Widget onboardingConversionPanel() {
      return StreamBuilder<Map<String, int>>(
        stream: UiTelemetryService.instance.countsStream,
        initialData: UiTelemetryService.instance.peekCounts(),
        builder: (context, snap) {
          final counts = snap.data ?? const <String, int>{};
          final guidedSelected = counts["onboarding_guided_selected"] ?? 0;
          final quickSelected = counts["onboarding_quick_selected"] ?? 0;
          final quickSuccess = counts["quick_setup_submit_success"] ?? 0;
          final quickFailed = counts["quick_setup_submit_failed"] ?? 0;
          final quickBlocked = counts["quick_setup_step_blocked"] ?? 0;

          return card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Onboarding conversion (session)",
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    pill("Guided selected: $guidedSelected", i: Icons.alt_route_outlined),
                    pill("Quick selected: $quickSelected", i: Icons.route_outlined),
                    pill("Quick success: $quickSuccess", i: Icons.check_circle_outline),
                    pill("Quick failed: $quickFailed", i: Icons.error_outline),
                    pill("Quick blocked: $quickBlocked", i: Icons.warning_amber_outlined),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "Session-local telemetry for tuning onboarding UX. Use for rapid iteration and tester reviews.",
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          );
        },
      );
    }

    Widget businessModePanel() {
      return StreamBuilder<PointsMeta>(
        stream: PointsService.instance.watchMeta(uid),
        builder: (context, snap) {
          final m = snap.data ?? PointsService.instance.peekMeta(uid);
          return FutureBuilder<BusinessGateState>(
            future: BusinessModeEligibility.gateForUser(uid: uid, meta: m),
            builder: (context, gateSnap) {
              final gate = gateSnap.data ?? BusinessModeEligibility.gateFromMeta(m);
              final businessUnlocked =
                  gate == BusinessGateState.eligible || gate == BusinessGateState.active;

              final trustRatio = _ratio(m.trustPercent, BusinessModeEligibility.minTrustPercent);
              final pointsRatio = _ratio(m.totalPoints, BusinessModeEligibility.minPoints);
              final meetRatio = _ratio(m.completedMeetups, BusinessModeEligibility.minCompletedMeetups);

              return card(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      "Business Mode",
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(width: 8),
                    TesterBadge(label: "Preview"),
                  ],
                ),
                const SizedBox(height: 8),
                BusinessModeGate(
                  state: gate,
                  onLearnMore: () {
                    UiTelemetryService.instance.log("business_gate_viewed", meta: {"source": "dashboard"});
                    go("/account");
                  },
                ),
                const SizedBox(height: 10),

                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    pill("Trust: ${m.trustPercent.toStringAsFixed(0)}%", i: Icons.verified_outlined),
                    pill("Points: ${m.totalPoints}", i: Icons.bolt),
                    pill("Meetups: ${m.completedMeetups}", i: Icons.handshake_outlined),
                  ],
                ),
                const SizedBox(height: 12),

                Text(
                  "Unlock progress",
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                progressRow(
                  label: "Trust",
                  valueText: "${m.trustPercent.toStringAsFixed(0)} / ${BusinessModeEligibility.minTrustPercent.toStringAsFixed(0)}",
                  ratio: trustRatio,
                  icon: Icons.verified_outlined,
                ),
                const SizedBox(height: 12),
                progressRow(
                  label: "Prox Points",
                  valueText: "${m.totalPoints} / ${BusinessModeEligibility.minPoints}",
                  ratio: pointsRatio,
                  icon: Icons.bolt,
                ),
                const SizedBox(height: 12),
                progressRow(
                  label: "Verified meetups",
                  valueText: "${m.completedMeetups} / ${BusinessModeEligibility.minCompletedMeetups}",
                  ratio: meetRatio,
                  icon: Icons.handshake_outlined,
                ),

                const SizedBox(height: 16),
                Text(
                  "Business items (preview)",
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),

                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => openBusinessItem(sku: "biz_boost_visibility", businessUnlocked: businessUnlocked),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.trending_up, color: cs.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Business Visibility Boost",
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        TesterBadge(label: "Business"),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => openBusinessItem(sku: "biz_provider_tools", businessUnlocked: businessUnlocked),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.work_outline, color: cs.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Provider Tools Pack",
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        TesterBadge(label: "Business"),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                Text(
                  gate == BusinessGateState.eligible
                      ? "You're eligible to unlock Business Mode."
                      : "Complete meetups and build trust to unlock Business Mode.",
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => go("/account"),
                      icon: const Icon(Icons.workspace_premium_outlined),
                      label: Text(
                        businessUnlocked ? "Manage Business" : "Unlock Business",
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => go("/nearby"),
                      icon: const Icon(Icons.radar_outlined),
                      label: const Text("Open Nearby ROI"),
                    ),
                  ],
                ),
              ],
            ),
              );
            },
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Dashboard"),
        actions: [
          FutureBuilder<bool>(
            future: DashboardAnnouncementsService.instance.isCurrentUserAdmin(),
            builder: (context, s) {
              final canOpen = s.data == true;
              if (!canOpen) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Creator Panel',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const CreatorPanelScreen()),
                  );
                },
                icon: const Icon(Icons.campaign),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: TesterBadge(label: "Tester")),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          sectionTitle("Announcements"),
          StreamBuilder<List<DashboardAnnouncement>>(
            stream: DashboardAnnouncementsService.instance.watchActive(),
            builder: (context, annSnap) {
              final announcements = annSnap.data == null || annSnap.data!.isEmpty
                  ? fallbackAnnouncements
                  : annSnap.data!;

              return card(
                child: Column(
                  children: [
                    for (final a in announcements)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          a.pinned ? Icons.push_pin_outlined : Icons.campaign_outlined,
                          color: cs.primary,
                        ),
                        title: Text(
                          a.title,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          a.body,
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          sectionTitle("Business"),
          businessModePanel(),
          const SizedBox(height: 16),

          sectionTitle("Onboarding"),
          onboardingConversionPanel(),
          const SizedBox(height: 16),

          sectionTitle("Your snapshot"),
          card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StreamBuilder<PointsMeta>(
                  stream: PointsService.instance.watchMeta(uid),
                  builder: (context, s) {
                    final m = s.data ?? PointsService.instance.peekMeta(uid);
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        pill("Points: ${m.totalPoints}", i: Icons.bolt),
                        pill("Trust: ${m.trustPercent.toStringAsFixed(0)}%", i: Icons.verified_outlined),
                        pill("Level: ${m.level}", i: Icons.stacked_line_chart),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<PartyMemberEntry>>(
                  stream: PartyService.instance.watchMyPartyEntries(),
                  builder: (context, s) {
                    final entries = s.data ?? const <PartyMemberEntry>[];
                    if (entries.isEmpty) {
                      return Text(
                        "No Party yet. Complete a meetup and add them to your Party.",
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      );
                    }
                    final mutual = entries.where((e) => e.mutual).length;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        pill("Party: ${entries.length}", i: Icons.group),
                        pill("Mutual: $mutual", i: Icons.handshake_outlined),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          metricsSection(),

          const SizedBox(height: 16),
          sectionTitle('Quick Tips'),
          _QuickTipsCard(
            onOpenSettings: () => go('/settings'),
          ),

          const SizedBox(height: 16),
          sectionTitle("Quick actions"),
          card(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.storefront_outlined, color: cs.primary),
                  title: const Text("Prox Points Store"),
                  subtitle: const Text("Locked items preview"),
                  onTap: () => go("/store"),
                ),
                Divider(height: 1, color: cs.outline.withValues(alpha: 0.20)),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.support_agent_outlined, color: cs.primary),
                  title: const Text("Support & feedback"),
                  subtitle: const Text("Report issues"),
                  onTap: () => go("/support"),
                ),
                Divider(height: 1, color: cs.outline.withValues(alpha: 0.20)),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.share_outlined, color: cs.primary),
                  title: const Text("Referrals"),
                  subtitle: const Text("Invite friends and track rewards"),
                  onTap: () => go("/referrals"),
                ),
                Divider(height: 1, color: cs.outline.withValues(alpha: 0.20)),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.qr_code_2_outlined, color: cs.primary),
                  title: const Text("Referral QR code"),
                  subtitle: const Text("Open and show your in-person invite QR"),
                  onTap: () => go("/referrals"),
                ),
                Divider(height: 1, color: cs.outline.withValues(alpha: 0.20)),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.credit_card_outlined, color: cs.primary),
                  title: const Text("Account & billing"),
                  subtitle: const Text("Business Mode"),
                  onTap: () => go("/account"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickTipsCard extends StatefulWidget {
  final VoidCallback onOpenSettings;

  const _QuickTipsCard({
    required this.onOpenSettings,
  });

  @override
  State<_QuickTipsCard> createState() => _QuickTipsCardState();
}

class _QuickTipsCardState extends State<_QuickTipsCard> {
  static const List<_TipLine> _tips = <_TipLine>[
    _TipLine('Hold the Prox Circle in Nearby to switch into active scanning when you are ready to meet now.'),
    _TipLine('After a successful meetup, add people to Party so reconnecting later is one tap away.'),
    _TipLine('Use Referrals in person with QR to speed up trust-building for new users you invite.'),
    _TipLine('If your list is crowded, Settings lets you tune match scope and radius for higher signal.'),
    _TipLine('Support and policy tools are always available from HQ when you need to report or appeal.'),
    _TipLine('Match quality improves when your profile has clear can-provide and searching-for keywords.'),
    _TipLine('Use Settings text size controls if you want easier scanning while moving quickly.'),
    _TipLine('Checking Trust timeline can explain why your score changed after recent activity.'),
    _TipLine('If meetup logistics are messy, lock a location first and then confirm arrival details in chat.'),
    _TipLine('Referrals work best when you explain what Prox solves before sharing your invite.'),
    _TipLine('Party labels help you triage who to contact first when you are time-limited.'),
    _TipLine('Discovery filters are your anti-noise controls when your nearby feed is too broad.'),
    _TipLine('Complete ratings after meetups to strengthen trust signals for both sides.'),
    _TipLine('Need accountability? Support and policy hubs are two taps away from HQ.'),
    _TipLine('Business unlock progress is easier to track from Dashboard than by memory alone.'),
    _TipLine('If radius is too wide, you are matching a map, not a moment. Tighten it.'),
    _TipLine('Profiles with real photos tend to convert to smoother first meetups.'),
    _TipLine('Use blocked users in Settings to keep your queue clean and focused.'),
    _TipLine('For first contact, one clear ask beats five vague messages every time.'),
    _TipLine('Tip from the Department of Obvious: replying fast helps conversations stay alive.', humorous: true),
    _TipLine('Puns are optional, clarity is not. Say what you need in one sentence first.', humorous: true),
    _TipLine('Nearby works best when your intent is current, not historical.'),
    _TipLine('If your plan requires six maybe steps, it probably needs one clearer next step.'),
    _TipLine('Trust grows slower than hype. That is annoying and useful.'),
    _TipLine('Party is your relationship memory so your brain can be used for better things.'),
    _TipLine('Quick reminder: ghosting hurts your momentum more than theirs.'),
    _TipLine('Yes, opening Settings can actually solve things. We were shocked too.', humorous: true),
    _TipLine('Support tickets with specifics get resolved faster than dramatic mystery novels.', humorous: true),
    _TipLine('Prox Points are handy, but reliability is still the real currency.'),
    _TipLine('If everyone is far away, reduce radius and try again in a busier zone.'),
    _TipLine('A simple meetup plan beats an elaborate maybe-plan with zero confirmations.'),
    _TipLine('Sarcastic update: unclear profiles are still unclear after refresh.', humorous: true),
    _TipLine('If chat stalls, ask one concrete question with a time option.'),
    _TipLine('Use policy and appeals tools early when something feels off.'),
    _TipLine('Trust pulse is useful context, not a substitute for direct communication.'),
    _TipLine('Your future self loves when you log outcomes right after each meetup.'),
    _TipLine('Tiny joke, huge truth: etiquette is a performance feature.', humorous: true),
    _TipLine('When in doubt, shorten the message and sharpen the ask.'),
    _TipLine('Referrals are stronger when the invite explains why now, not just why someday.'),
    _TipLine('No app can schedule your priorities for you. We tried.', humorous: true),
    _TipLine('The fastest path to fewer bad matches is better profile specificity.'),
    _TipLine('If you keep seeing noise, match scope controls are probably overdue for tuning.'),
    _TipLine('Meetup confirmations are boring and highly effective. Keep doing them.'),
    _TipLine('Comic relief break: your inbox called, it wants fewer half-plans.', humorous: true),
    _TipLine('Helpful cynicism: if it is not scheduled, it is a wish.', humorous: true),
    _TipLine('Use User\'s Guide in Settings for complete feature and button pipelines.'),
  ];

  static const Duration _cycleEvery = Duration(seconds: 22);
  static const int _humorEvery = 5;

  final Random _random = Random();
  Timer? _timer;
  late List<int> _cycleOrder;
  int _cyclePos = 0;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _rebuildCycleOrder();
    if (_cycleOrder.isNotEmpty) {
      _index = _cycleOrder.first;
    }
    _timer = Timer.periodic(_cycleEvery, (_) {
      if (!mounted) return;
      _advancePhrase();
    });
  }

  void _rebuildCycleOrder({int? avoidFirst}) {
    final all = List<int>.generate(_tips.length, (i) => i);
    final useful = all.where((i) => !_tips[i].humorous && i != avoidFirst).toList(growable: true);
    final humorous = all.where((i) => _tips[i].humorous && i != avoidFirst).toList(growable: true);
    useful.shuffle(_random);
    humorous.shuffle(_random);

    final List<int> order = <int>[];

    // Strict cadence: build random 5-message groups with exactly 1 humorous + 4 useful.
    bool previousEndedHumorous = false;
    while (humorous.isNotEmpty && useful.length >= _humorEvery - 1) {
      final chunkUseful = List<int>.generate(_humorEvery - 1, (_) => useful.removeLast());
      final humorousLine = humorous.removeLast();

      int humorPos = _random.nextInt(_humorEvery);
      if (previousEndedHumorous && humorPos == 0) {
        humorPos = 1 + _random.nextInt(_humorEvery - 1);
      }

      for (int i = 0; i < _humorEvery; i += 1) {
        if (i == humorPos) {
          order.add(humorousLine);
        } else {
          order.add(chunkUseful.removeLast());
        }
      }
      previousEndedHumorous = humorPos == _humorEvery - 1;
    }

    // Any leftovers are useful lines only, so no humor clumping can occur.
    while (useful.isNotEmpty) {
      order.add(useful.removeLast());
    }

    _cycleOrder = order;
    _cyclePos = 0;
  }

  void _advancePhrase() {
    if (_tips.length < 2) return;

    setState(() {
      _cyclePos += 1;
      if (_cyclePos >= _cycleOrder.length) {
        _rebuildCycleOrder(avoidFirst: _index);
      }
      if (_cycleOrder.isNotEmpty) {
        _index = _cycleOrder[_cyclePos];
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Tip Cycler',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Text(
                'Rotates slowly',
                style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
              final slide = Tween<Offset>(
                begin: const Offset(0.03, 0),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: fade,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: Text(
              _tips[_index].text,
              key: ValueKey<int>(_index),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Need the full walkthrough? Open Settings and tap User's Guide for complete feature pipelines.",
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: widget.onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

class _TipLine {
  final String text;
  final bool humorous;

  const _TipLine(this.text, {this.humorous = false});
}