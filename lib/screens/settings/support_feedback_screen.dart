import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "package:prox/services/feedback_service.dart";

class SupportFeedbackScreen extends StatefulWidget {
  const SupportFeedbackScreen({super.key});

  @override
  State<SupportFeedbackScreen> createState() => _SupportFeedbackScreenState();
}

class _SupportFeedbackScreenState extends State<SupportFeedbackScreen> {
  ProxFeedbackType _type = ProxFeedbackType.bug;
  int _devComboStep = 0;

  final TextEditingController _text = TextEditingController();
  final TextEditingController _huh = TextEditingController();

  bool _submitting = false;

  static const String _elaborateUrl = "https://prox-us.com/support";
  static const List<ProxFeedbackType> _devComboPattern = <ProxFeedbackType>[
    ProxFeedbackType.feedback,
    ProxFeedbackType.bug,
    ProxFeedbackType.comment,
  ];
  static const int _devComboCycles = 5;

  @override
  void dispose() {
    _text.dispose();
    _huh.dispose();
    super.dispose();
  }

  Future<void> _copyElaborateLink() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(const ClipboardData(text: _elaborateUrl));
    messenger.showSnackBar(
      const SnackBar(content: Text("Link copied. Paste into your browser to elaborate.")),
    );
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);

    final body = _text.text.trim();
    if (body.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text("Type a quick note first.")));
      return;
    }

    setState(() => _submitting = true);
    try {
      await FeedbackService.instance.submit(
        type: _type,
        text: body,
        firstHuhMoment: _huh.text.trim(),
        source: "settings_support_feedback",
      );

      if (!mounted) return;

      _text.clear();
      _huh.clear();

      messenger.showSnackBar(
        SnackBar(content: Text("${_type.label} sent. Thank you ")),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't send. $e")),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _selectTypeFromChip(ProxFeedbackType selectedType) {
    setState(() => _type = selectedType);
    _trackDevCombo(selectedType);
  }

  void _trackDevCombo(ProxFeedbackType selectedType) {
    final expected = _devComboPattern[_devComboStep % _devComboPattern.length];
    if (selectedType == expected) {
      _devComboStep += 1;
    } else {
      _devComboStep = selectedType == _devComboPattern.first ? 1 : 0;
    }

    final neededSteps = _devComboPattern.length * _devComboCycles;
    if (_devComboStep >= neededSteps) {
      _devComboStep = 0;
      if (!mounted) return;
      Navigator.of(context).pushNamed("/dev/menu");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final tip = switch (_type) {
      ProxFeedbackType.bug =>
        "Bug reports that include the screen you were on + what you tapped are legendary.",
      ProxFeedbackType.feedback =>
        "Feature ideas are best when they start with the goal (what you wanted to do).",
      ProxFeedbackType.comment =>
        "Quick vibes are useful too. Confusing? Smooth? Creepy? Great? Tell us.",
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text("Support & feedback"),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.support_agent_outlined, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Fast feedback is rocket fuel for Prox.\n"
                    "Tip: include a screenshot when something is confusing or broken.\n"
                    "Keep it short - we'll follow up if needed.",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Text("Type", style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                selected: _type == ProxFeedbackType.feedback,
                label: const Text("Feedback"),
                onSelected: (_) => _selectTypeFromChip(ProxFeedbackType.feedback),
              ),
              ChoiceChip(
                selected: _type == ProxFeedbackType.bug,
                label: const Text("Bug Report"),
                onSelected: (_) => _selectTypeFromChip(ProxFeedbackType.bug),
              ),
              ChoiceChip(
                selected: _type == ProxFeedbackType.comment,
                label: const Text("Comment"),
                onSelected: (_) => _selectTypeFromChip(ProxFeedbackType.comment),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Text(
            tip,
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),

          const SizedBox(height: 16),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 8,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              labelText: _type == ProxFeedbackType.bug ? "What broke?" : "What is on your mind?",
              hintText: _type == ProxFeedbackType.bug
                  ? "Example: Nearby list shows someone as fresh even when they were offline."
                  : "Example: I want a Meetup Now button on the chat header.",
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),

          const SizedBox(height: 12),
          TextField(
            controller: _huh,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: "First confusion moment (optional)",
              hintText: "Example: I did not understand Party vs Public at first.",
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),

          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_submitting ? "Sending..." : "Send"),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _copyElaborateLink,
                icon: const Icon(Icons.open_in_new),
                label: const Text("Elaborate"),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Text(
            "Elaborate copies the support link so you can paste it into your browser. "
            "We keep the in-app flow fast to maximize response rate.",
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

