import "package:flutter/material.dart";
import "package:firebase_auth/firebase_auth.dart";

import "package:prox/services/policy_ack_service.dart";
import "package:prox/services/points_service.dart";

class CodeOfConductScreen extends StatelessWidget {
  const CodeOfConductScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // ignore: discarded_futures
    PolicyAckService.instance.ensureLoaded();

    final text = [
      "Code of Conduct (v1)",
      "",
      "Prox is built for real-world connection. That only works if people feel safe.",
      "",
      "1) Be honest",
      " No scams, fraud, or deceptive intent.",
      " No impersonation.",
      "",
      "2) Be lawful",
      " Do not use Prox to plan or offer illegal activity.",
      "",
      "3) Be safe",
      " No threats, coercion, harassment, stalking, or intimidation.",
      " Respect boundaries. If someone says no, it's no.",
      "",
      "4) Be respectful",
      " Treat people like humans. Don't bait, shame, or abuse.",
      "",
      "5) Protect the platform",
      " Don't exploit referrals, points, support mode, or any system.",
      "",
      "Enforcement is evidence-based.",
      "If a serious integrity issue occurs, Business Mode can be suspended or an account restricted/banned.",
      "Users may submit an explanation and supporting evidence through the appeal flow.",
    ].join("\n");

    return Scaffold(
      appBar: AppBar(title: const Text("Code of Conduct")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
            ),
            child: SelectableText(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.25),
            ),
          ),
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation: PolicyAckService.instance,
            builder: (context, _) {
              final svc = PolicyAckService.instance;
              final ok = svc.isAcked(PolicyAckService.conductVersion);

              return SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: ok ? null : () async {
                    await svc.setAcked(PolicyAckService.conductVersion, true);
                    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
                    if (uid.trim().isNotEmpty) {
                      await PointsService.instance.addPoints(
                        uid: uid,
                        amount: 10,
                        reason: "Accepted Code of Conduct",
                        category: "policy_ack",
                        contextType: "conduct",
                      );
                    }
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Accepted: Code of Conduct (+10 Prox Points)")));
                  },
                  icon: Icon(ok ? Icons.check_circle : Icons.done),
                  label: Text(ok ? "Accepted" : "I understand & accept"),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}