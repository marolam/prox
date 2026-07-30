import "package:flutter/widgets.dart";

class TutorialTarget extends StatelessWidget {
  const TutorialTarget({
    super.key,
    required this.id,
    required this.message,
    required this.child,
  });

  final String id;
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
