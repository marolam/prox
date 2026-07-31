import "package:flutter/material.dart";
import "package:firebase_auth/firebase_auth.dart";

import "package:prox/widgets/prox_points_badge.dart";
import "package:prox/services/prox_points_service.dart";

/// Developer-only screen to poke at Prox Points behavior:
/// - Shows live badge for current user.
/// - Buttons to add small / large point chunks.
/// - Handy for verifying Firestore integration and level curve.
class DevPointsDemoScreen extends StatefulWidget {
  static const String routeName = "/dev/points-demo";

  const DevPointsDemoScreen({super.key});

  @override
  State<DevPointsDemoScreen> createState() => _DevPointsDemoScreenState();
}

class _DevPointsDemoScreenState extends State<DevPointsDemoScreen> {
  bool _busy = false;
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> _add(int delta) async {
    final uid = _uid;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No user signed in.")),
      );
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ProxPointsService.instance.addPoints(uid: uid, delta: delta);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Added $delta points.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to add points: $e")),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Prox Points Demo"),
        actions: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: ProxPointsBadge()),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: uid == null
            ? const Center(child: Text("Sign in to test Prox Points."))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "UID:",
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  SelectableText(
                    uid,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Live Points Badge",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const ProxPointsBadge(),
                  const SizedBox(height: 24),
                  const Text(
                    "Mutations",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: _busy ? null : () => _add(5),
                        child: const Text("+5 (tiny)"),
                      ),
                      ElevatedButton(
                        onPressed: _busy ? null : () => _add(25),
                        child: const Text("+25 (small)"),
                      ),
                      ElevatedButton(
                        onPressed: _busy ? null : () => _add(100),
                        child: const Text("+100 (chunk)"),
                      ),
                      ElevatedButton(
                        onPressed: _busy ? null : () => _add(500),
                        child: const Text("+500 (big test)"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Notes",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "- Points & levels are placeholder logic.\n"
                    "- Document lives at users/{uid}/meta/points.\n"
                    "- Safe to delete/reset manually while experimenting.",
                  ),
                ],
              ),
      ),
    );
  }
}
