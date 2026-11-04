import "package:flutter/material.dart";

class ProfileKeywordChip extends StatelessWidget {
  const ProfileKeywordChip({
    super.key,
    required this.keyword,
    required this.active,
    required this.accentColor,
    required this.onToggle,
    required this.onRemove,
  });

  final String keyword;
  final bool active;
  final Color accentColor;
  final VoidCallback? onToggle;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 380;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: active
            ? [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.30),
                  blurRadius: 6,
                  spreadRadius: 0.4,
                ),
              ]
            : null,
      ),
      child: InputChip(
        label: Text(keyword),
        labelStyle: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
        selected: active,
        showCheckmark: false,
        backgroundColor: cs.surface.withValues(alpha: 0.18),
        selectedColor: cs.surface.withValues(alpha: 0.18),
        shape: const StadiumBorder(),
        side: BorderSide(
          color: active ? accentColor : cs.primary.withValues(alpha: 0.55),
          width: active ? 1.8 : 1,
        ),
        padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6),
        tooltip: active
            ? "Turn off matching for $keyword"
            : "Activate $keyword",
        onPressed: onToggle,
        onDeleted: onRemove,
        deleteButtonTooltipMessage: "Remove $keyword",
      ),
    );
  }
}
