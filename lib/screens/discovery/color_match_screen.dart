import "package:flutter/material.dart";
import "package:prox/models/color_match_models.dart";

class ColorMatchScreen extends StatefulWidget {
  const ColorMatchScreen({
    super.key,
    this.initialColor = MatchColor.red,
    this.meetupId = "",
    this.onDismiss,
  });

  final MatchColor initialColor;
  final String meetupId;
  final VoidCallback? onDismiss;

  @override
  State<ColorMatchScreen> createState() => _ColorMatchScreenState();
}

class _ColorMatchScreenState extends State<ColorMatchScreen> {
  late MatchColor _selected = widget.initialColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Color Match")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final color in MatchColor.values)
            RadioListTile<MatchColor>(
              value: color,
              groupValue: _selected,
              title: Text(color.name),
              onChanged: (next) {
                if (next == null) return;
                setState(() => _selected = next);
              },
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              widget.onDismiss?.call();
              Navigator.of(context).pop(_selected);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }
}
