import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "package:prox/screens/settings/support_feedback_screen.dart";
import "package:prox/services/build_info_service.dart";
import "package:prox/services/user_settings_service.dart";

class TesterMenuScreen extends StatefulWidget {
  const TesterMenuScreen({super.key});

  @override
  State<TesterMenuScreen> createState() => _TesterMenuScreenState();
}

class _TesterMenuScreenState extends State<TesterMenuScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String _statusReport = "No status report pulled yet.";
  bool _loading = false;

  Future<String> _buildStatusReport() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? "";
    final now = DateTime.now().toUtc().toIso8601String();
    final build = BuildInfoService.instance.info;
    final settings = UserSettingsService.instance.current;

    Map<String, dynamic> points = const <String, dynamic>{};
    Map<String, dynamic> stats = const <String, dynamic>{};

    if (uid.isNotEmpty) {
      final pointsSnap = await _db
          .collection("users")
          .doc(uid)
          .collection("meta")
          .doc("points")
          .get();
      points = pointsSnap.data() ?? const <String, dynamic>{};

      final statsSnap = await _db
          .collection("users")
          .doc(uid)
          .collection("stats")
          .doc("current")
          .get();
      stats = statsSnap.data() ?? const <String, dynamic>{};
    }

    int readInt(Map<String, dynamic> data, String key) {
      final v = data[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return 0;
    }

    final lines = <String>[
      "PROX STATUS REPORT",
      "capturedAtUtc: $now",
      "",
      "USER",
      "uid: ${uid.isEmpty ? "(signed out)" : uid}",
      "email: ${user?.email ?? ""}",
      "",
      "BUILD",
      "version: ${build.version}",
      "build: ${build.build}",
      "builtAtUtc: ${build.builtAt.millisecondsSinceEpoch <= 0 ? "unknown" : build.builtAt.toUtc().toIso8601String()}",
      "",
      "SETTINGS",
      "uxMode: ${settings.uxMode.name}",
      "textScale: ${settings.textScaleFactor.toStringAsFixed(2)}",
      "trustPulse: ${settings.trustPulseEnabled}",
      "referralSignal: ${settings.referralSignalEnabled}",
      "matchModeKind: ${settings.matchDiscovery.modeKind.name}",
      "normalMatchMode: ${settings.matchDiscovery.normalMode.name}",
      "radiusMiles: ${settings.matchDiscovery.radiusMiles.toStringAsFixed(1)}",
      "treasureRadiusMiles: ${settings.matchDiscovery.treasureRadiusMiles.toStringAsFixed(1)}",
      "businessOnly: ${settings.matchDiscovery.businessOnly}",
      "immediateOnly: ${settings.matchDiscovery.immediateOnly}",
      "activePenaltyCount: ${settings.matchDiscovery.activePenaltyCount}",
      "activeLockUntilEpochMs: ${settings.matchDiscovery.activeLockUntilEpochMs}",
      "",
      "POINTS",
      "currentPoints: ${readInt(points, "currentPoints")}",
      "totalPoints: ${readInt(points, "totalPoints")}",
      "lifetimePoints: ${readInt(points, "lifetimePoints")}",
      "level: ${readInt(points, "level")}",
      "trustScore: ${readInt(points, "trustScore")}",
      "",
      "TESTER STATS",
      "bugsReported: ${readInt(stats, "bugsReported")}",
      "evidenceReports: ${readInt(stats, "evidenceReports")}",
      "meetupsCompleted: ${readInt(stats, "meetupsCompleted")}",
      "referralsVerified: ${readInt(stats, "referralsVerified")}",
      "feedbackHelpfulVotes: ${readInt(stats, "feedbackHelpfulVotes")}",
      "feedbackScore100: ${readInt(stats, "feedbackScore100")}",
      "feedbackScoreSamples: ${readInt(stats, "feedbackScoreSamples")}",
    ];

    return lines.join("\n");
  }

  Future<void> _pullStatusReport() async {
    setState(() => _loading = true);
    try {
      final report = await _buildStatusReport();
      if (!mounted) return;
      setState(() => _statusReport = report);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Current status report pulled.")),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not pull status report.")),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: _statusReport));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Status report copied to clipboard.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Tester Menu")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          FilledButton.icon(
            onPressed: _loading ? null : _pullStatusReport,
            icon: const Icon(Icons.summarize_outlined),
            label: Text(_loading ? "Pulling..." : "Pull Current Status Report"),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _copyReport,
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text("Copy Status Report"),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const SupportFeedbackScreen()),
              );
            },
            icon: const Icon(Icons.feedback_outlined),
            label: const Text("Open Feedback"),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pushNamed("/dev/menu");
            },
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text("Open Advanced Diagnostics"),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.25)),
            ),
            child: SelectableText(
              _statusReport,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
