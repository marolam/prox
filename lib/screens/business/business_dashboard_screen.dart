import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "package:prox/models/dashboard_metrics.dart";
import "package:share_plus/share_plus.dart";

import "package:prox/screens/profile/profile_edit_screen.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/screens/services/points_service.dart";
import "package:prox/services/dashboard_metrics_service.dart";
import "package:prox/services/match_events_service.dart";
import "package:prox/services/user_profile_service.dart";

class BusinessDashboardScreen extends StatelessWidget {
  const BusinessDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.trim().isEmpty) {
      return const Scaffold(body: Center(child: Text("Not signed in")));
    }

    Widget card({required Widget child}) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
          ),
          child: child,
        );

    Widget metricChip(String label, String value, IconData icon) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(label, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        );

    void openProfileEdit() {
      final previous = ContextHelpService.instance.contextKey.value;
      ContextHelpService.instance.setContext("business:hq_profile_edit");
      // ignore: discarded_futures
      Navigator.of(context)
          .push(
        MaterialPageRoute<void>(builder: (_) => const ProfileEditScreen(fromOnboarding: false)),
      )
          .then((_) {
        ContextHelpService.instance.setContext(previous);
      });
    }

    void shareProfile() {
      Share.share(
        "Find me on Prox - fast local help and professional service."
        "\nOpen the app and search my name in Business Mode.",
      );
    }

    void postOffer() {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Offer posting is coming next.")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Business HQ"),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.primary.withValues(alpha: 0.30),
                  cs.surfaceContainerHighest,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: cs.outline.withValues(alpha: 0.20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Run your local business on Prox",
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  "Be reachable, respond fast, and close meetups with clarity.",
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: openProfileEdit,
                      icon: const Icon(Icons.schedule_outlined),
                      label: const Text("Set availability"),
                    ),
                    OutlinedButton.icon(
                      onPressed: shareProfile,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text("Share profile"),
                    ),
                    OutlinedButton.icon(
                      onPressed: postOffer,
                      icon: const Icon(Icons.sell_outlined),
                      label: const Text("Post an offer"),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Pipeline snapshot", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                StreamBuilder<PointsMeta>(
                  stream: PointsService.instance.watchMeta(uid),
                  builder: (context, snap) {
                    final meta = snap.data ?? PointsService.instance.peekMeta(uid);
                    final leads = MatchEventsService.instance.readEvents().length;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        metricChip("Leads", leads.toString(), Icons.auto_graph_outlined),
                        metricChip("Meetups", meta.completedMeetups.toString(), Icons.handshake_outlined),
                        metricChip("Trust", meta.trustPercent.toStringAsFixed(0), Icons.verified_outlined),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          card(
            child: StreamBuilder<DashboardMetrics?>(
              stream: DashboardMetricsService.instance.watchMetrics(),
              builder: (context, snap) {
                final metrics = snap.data;
                final top = metrics?.topKeywords ?? const <KeywordMetric>[];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Market pulse", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        metricChip("Total users", metrics?.totalUsers.toString() ?? "-", Icons.groups_outlined),
                        metricChip("New today", metrics?.newUsersToday.toString() ?? "-", Icons.trending_up),
                      ],
                    ),
                    if (top.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text("Top keywords", style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: top
                            .take(6)
                            .map(
                              (k) => Chip(
                                label: Text("${k.keyword}  ${k.count}"),
                                avatar: const Icon(Icons.local_fire_department_outlined, size: 16),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          card(
            child: StreamBuilder<UserProfile?>(
              stream: UserProfileService.instance.watchProfile(uid),
              builder: (context, snap) {
                final profile = snap.data;
                final name = (profile?.displayName ?? "").trim();
                final availability = profile?.availabilityMinutes ?? 0;
                final availabilityLabel = availability == 0
                    ? "Immediate"
                    : "Within ${availability}m";

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Availability", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      name.isNotEmpty ? "$name is $availabilityLabel" : "You are $availabilityLabel",
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
