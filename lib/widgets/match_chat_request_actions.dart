import 'package:flutter/material.dart';

/// The recipient's next step, shown across the full width of a match card.
class MatchChatRequestActions extends StatefulWidget {
  const MatchChatRequestActions({
    super.key,
    required this.onAccept,
    required this.onDecline,
  });

  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;

  @override
  State<MatchChatRequestActions> createState() =>
      _MatchChatRequestActionsState();
}

class _MatchChatRequestActionsState extends State<MatchChatRequestActions> {
  bool? _accepting;

  Future<void> _respond(bool accept) async {
    if (_accepting != null) return;
    setState(() => _accepting = accept);
    try {
      await (accept ? widget.onAccept() : widget.onDecline());
    } finally {
      if (mounted) setState(() => _accepting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final busy = _accepting != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.10),
        border: Border.all(color: colors.primary.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your next step: respond',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text('Accept to open chat, or decline this request.'),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final accept = FilledButton.icon(
                onPressed: busy ? null : () => _respond(true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 56),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: _accepting == true
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _accepting == true ? 'Accepting…' : 'Accept chat',
                  textAlign: TextAlign.center,
                ),
              );
              final decline = OutlinedButton.icon(
                onPressed: busy ? null : () => _respond(false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 56),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  foregroundColor: colors.onSurface,
                  side: BorderSide(color: colors.outline),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: _accepting == false
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.close),
                label: Text(
                  _accepting == false ? 'Declining…' : 'Decline chat',
                  textAlign: TextAlign.center,
                ),
              );
              if (constraints.maxWidth < 360 ||
                  MediaQuery.textScalerOf(context).scale(16) > 20) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [accept, const SizedBox(height: 10), decline],
                );
              }
              return Row(
                children: [
                  Expanded(child: accept),
                  const SizedBox(width: 12),
                  Expanded(child: decline),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
