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
    return IconButton(
      icon: const Icon(Icons.palette_outlined),
      tooltip: "Color match",
      onPressed: () {
        onStarted?.call();
        Navigator.of(context).pushNamed("/color-match", arguments: meetupId);
      },
    );
  }
}
