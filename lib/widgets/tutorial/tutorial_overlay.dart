import "package:flutter/widgets.dart";

class TutorialOverlayHost extends StatelessWidget {
  const TutorialOverlayHost({
    super.key,
    required this.child,
    this.logoTopPadding,
    this.logoLeftPadding,
  });

  final Widget child;
  final double? logoTopPadding;
  final double? logoLeftPadding;

  @override
  Widget build(BuildContext context) => child;
}

class TutorialOverlay extends StatelessWidget {
  const TutorialOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TutorialOverlayHost(child: child);
}
