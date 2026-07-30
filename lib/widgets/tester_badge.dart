import "package:flutter/material.dart";

class TesterBadge extends StatelessWidget {
  const TesterBadge({
    super.key,
    required this.label,
    this.semanticsLabel,
  });

  final String label;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel ?? label,
      child: Chip(
        label: Text(label),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}