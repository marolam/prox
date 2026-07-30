import "package:flutter/material.dart";

import "package:prox/widgets/prox_glass.dart";

/// MatchFoundSheet
///
/// UI-only mockup-aligned sheet. You can show it from anywhere:
///
/// await showModalBottomSheet(
///   context: context,
///   backgroundColor: Colors.transparent,
///   isScrollControlled: true,
///   builder: (_) => MatchFoundSheet(...),
/// );
class MatchFoundSheet extends StatelessWidget {
  const MatchFoundSheet({
    super.key,
    required this.distanceLabel,
    required this.keywords,
    required this.onIgnore,
    required this.onSayHi,
  });

  final String distanceLabel;
  final List<String> keywords;
  final VoidCallback onIgnore;
  final VoidCallback onSayHi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final k = keywords.take(3).toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            "Match found",
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.primary.withValues(alpha: 0.95),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            "Someone nearby right now",
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withValues(alpha: 0.88),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),

          ProxGlass(
            radius: 22,
            blurSigma: 20,
            fillOpacity: 0.10,
            borderOpacity: 0.16,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      distanceLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface.withValues(alpha: 0.90),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final w in k)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: cs.surface.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: cs.outline.withValues(alpha: 0.16)),
                        ),
                        child: Text(
                          w,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface.withValues(alpha: 0.88),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF15D6A6),
                        Color(0xFFB6D61A),
                        Color(0xFFFFB000),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ProxGlassButton(
                  label: "Ignore",
                  onTap: onIgnore,
                  highlight: cs.outlineVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ProxGlassButton(
                  label: "Say hi",
                  onTap: onSayHi,
                  highlight: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "Visible only while you're nearby.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
