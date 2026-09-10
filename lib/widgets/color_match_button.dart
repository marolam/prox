import "package:flutter/material.dart";

class ColorMatchButton extends StatelessWidget {
  const ColorMatchButton({
    super.key,
    required this.meetupId,
    this.onStarted,
  });

  final String meetupId;
  final VoidCallback? onStarted;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      icon: const Icon(Icons.wb_sunny_outlined),
      label: const Text("Find each other"),
      onPressed: () {
        onStarted?.call();
        Navigator.of(context).pushNamed("/color-match", arguments: meetupId);
      },
    );
  }
}
