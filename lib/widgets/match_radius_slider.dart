import "package:flutter/material.dart";

class MatchRadiusSlider extends StatelessWidget {
  const MatchRadiusSlider({super.key, required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Radius: ${value.toStringAsFixed(1)} mi"),
        Slider(value: value.clamp(0.5, 25), min: 0.5, max: 25, divisions: 49, onChanged: onChanged),
      ],
    );
  }
}