import "package:flutter/material.dart";

class MatchFilterChip extends StatelessWidget {
  const MatchFilterChip({super.key, required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(label: Text(label), selected: selected, onSelected: onTap == null ? null : (_) => onTap!());
  }
}