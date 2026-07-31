import "package:flutter/material.dart";
import "package:prox/services/ui_telemetry_service.dart";

enum BusinessGateState {
  locked,
  eligible,
  active,
}

class BusinessModeGate extends StatelessWidget {
  final BusinessGateState state;
  final VoidCallback? onLearnMore;

  const BusinessModeGate({
    super.key,
    required this.state,
    this.onLearnMore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    String title;
    String body;
    IconData icon;

    switch (state) {
      case BusinessGateState.active:
        title = "Business Mode active";
        body = "You're running Prox in Business Mode.";
        icon = Icons.verified_outlined;
        break;
      case BusinessGateState.eligible:
        title = "Business Mode available";
        body = "You're eligible to unlock Business Mode.";
        icon = Icons.trending_up;
        break;
      case BusinessGateState.locked:
        title = "Business Mode locked";
        body = "Earn trust and Prox Points to unlock Business Mode.";
        icon = Icons.lock_outline;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(body, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                if (onLearnMore != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () {
                      UiTelemetryService.instance.log(
                        "business_info_opened",
                        meta: {"source": "business_gate"},
                      );
                      onLearnMore!();
                    },
                    child: const Text("Learn more"),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}