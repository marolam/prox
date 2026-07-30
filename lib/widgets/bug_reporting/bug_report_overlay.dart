import "package:flutter/material.dart";

class BugReportOverlay extends StatelessWidget {
  const BugReportOverlay({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}