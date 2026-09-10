import "package:flutter/material.dart";

class SimpleModeChoiceScreen extends StatefulWidget {
  const SimpleModeChoiceScreen({
    super.key,
    required this.onSelectSimple,
    required this.onSelectNormal,
  });

  final VoidCallback onSelectSimple;
  final ValueChanged<bool> onSelectNormal;

  @override
  State<SimpleModeChoiceScreen> createState() => _SimpleModeChoiceScreenState();
}

class _SimpleModeChoiceScreenState extends State<SimpleModeChoiceScreen> {
  bool _alwaysUseNormalMode = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text("Choose your Prox mode"),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                "Choose the experience that feels right for you.",
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                "Simple Mode is the everyday Big-5 experience with extra features hidden. It keeps helping each time through the flow, and you can move to Normal Mode later.",
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _modeCard(
                context,
                icon: Icons.assistant_navigation,
                title: "Simple Mode",
                subtitle: "A trimmed-down app with clear next actions.",
                bullets: const [
                  "Only Profile, Nearby, active chat, and Meetups",
                  "Normal matching with Active and Passive",
                  "Fixed, beginner-friendly search defaults",
                ],
              ),
              const SizedBox(height: 12),
              _modeCard(
                context,
                icon: Icons.tune,
                title: "Normal Mode",
                subtitle:
                    "Full controls and advanced options available immediately.",
                bullets: const [
                  "All discovery controls visible",
                  "No guided hand-holding",
                  "Best for experienced users",
                ],
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                value: _alwaysUseNormalMode,
                onChanged: (v) {
                  setState(() => _alwaysUseNormalMode = v == true);
                },
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text("Always use Normal Mode"),
                subtitle: const Text(
                  "If enabled, this chooser is skipped next login.",
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: widget.onSelectSimple,
                icon: const Icon(Icons.play_arrow),
                label: const Text("Use Simple Mode"),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => widget.onSelectNormal(_alwaysUseNormalMode),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text("Continue in Normal Mode"),
              ),
              const SizedBox(height: 12),
              Text(
                "Reminder: you can always switch back to Simple Mode in Settings.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<String> bullets,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final bullet in bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                "- $bullet",
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
