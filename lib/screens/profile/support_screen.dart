// lib/screens/profile/support_screen.dart
//
// Simple Support/Help UI for early testers.
// Lets a user log that they helped someone (support session) and
// awards Prox Points via PointsService.addPoints with category "support".

import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "package:prox/services/points_service.dart";

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final TextEditingController _noteController = TextEditingController();
  int _sessions = 1;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitSupport() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack("You need to be signed in to earn support points.");
      return;
    }
    if (_isSubmitting) return;
    if (_sessions <= 0) {
      _showSnack("Please choose at least one support session.");
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final reason = _noteController.text.trim();
      final sessionId = "support_${DateTime.now().millisecondsSinceEpoch}";
      final amount = 20 * _sessions; // early-tester support reward

      await PointsService.instance.addPoints(
        uid: user.uid,
        amount: amount,
        category: "support",
        reason: reason.isNotEmpty ? reason : "Support session",
        contextId: sessionId,
        contextType: "support",
      );

      _noteController.clear();
      _sessions = 1;
      _showSnack("Support recorded. You earned Prox Points!");
    } catch (e) {
      _showSnack("Could not record support session right now.");
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Help & earn"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: cs.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Earn points for helping others",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "When you help someone with Prox (questions, setup, troubleshooting, "
                    "moderation, etc.), you can log it here to earn Prox Points.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: cs.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "What did you help with?",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _noteController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText:
                          "Short note (e.g. \"Helped Sarah install & set up keywords\")",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "How many support sessions?",
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _sessions > 1
                            ? () {
                                setState(() {
                                  _sessions -= 1;
                                });
                              }
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text(
                        "$_sessions",
                        style: theme.textTheme.titleMedium,
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _sessions += 1;
                          });
                        },
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Each session grants about 20 points.",
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isSubmitting ? null : _submitSupport,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.volunteer_activism_outlined),
                      label: Text(
                        _isSubmitting ? "Recording..." : "Record support",
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Use this for genuine support/help. Abuse of this may reduce trust later.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
