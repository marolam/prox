import "package:flutter/material.dart";
import "package:firebase_auth/firebase_auth.dart";

import "package:prox/services/policy_ack_service.dart";
import "package:prox/services/points_service.dart";

class BusinessRulesScreen extends StatelessWidget {
  const BusinessRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // ignore: discarded_futures
    PolicyAckService.instance.ensureLoaded();

    final text = [
      "Business Mode rules & expectations (v1)",
      "",
      "What Business Mode is",
      "Business Mode is for people who are open to fast, reliable, real-world meetups or services.",
      "It's not about being a company - it's about clear intent, follow-through, and trust.",
      "Business Mode is a privilege earned through trustworthy personal use.",
      "",
      "What's expected",
      " Respond within a reasonable time",
      " Show up to meetups you accept",
      " Keep availability honest",
      " Communicate clearly if plans change",
      " If you mark Immediate, you must stay truly available",
      "",
      "How visibility works",
      "Business Mode visibility is dynamic.",
      "Your profile appears more when you respond, arrive on time, complete meetups, and keep availability accurate.",
      "Your profile appears less when you miss meetups, repeatedly cancel without notice, or set Immediate while inactive.",
      "This is signal quality, not punishment. Everything recovers with normal use.",
      "If response reliability drops, Prox may automatically move you back to Personal Mode.",
      "Re-entry to Business Mode can be delayed (typically 20-60+ minutes) to protect user trust.",
      "",
      "What Prox does NOT do",
      " No permanent penalties for honest mistakes",
      " No hidden bans",
      " No forced payments",
      " No selling/sharing your data",
      "",
      "Leaving Business Mode",
      "You can switch back anytime. You stop appearing in Business searches.",
      "Your trust, history, and Party connections remain intact.",
    ].join("\n");

    return Scaffold(
      appBar: AppBar(title: const Text("Business Mode rules")),
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
              final ok = svc.isAcked(PolicyAckService.businessRulesVersion);

              return SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: ok ? null : () async {
                    await svc.setAcked(PolicyAckService.businessRulesVersion, true);
                    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
                    if (uid.trim().isNotEmpty) {
                      await PointsService.instance.addPoints(
                        uid: uid,
                        amount: 15,
                        reason: "Accepted Business Mode rules",
                        category: "policy_ack",
                        contextType: "business_rules",
                      );
                    }
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Accepted: Business rules (+15 Prox Points)")));
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