import "package:flutter/material.dart";

class CostHudOverlay extends StatelessWidget {
  const CostHudOverlay({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}