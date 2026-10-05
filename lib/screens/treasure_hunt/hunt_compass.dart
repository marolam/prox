import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:prox/services/matching/treasure_compass_service.dart';

class HuntCompass extends StatelessWidget {
  const HuntCompass({
    super.key,
    required this.bearingDegrees,
    this.distanceMiles = 5,
  });
  final double bearingDegrees;
  final double distanceMiles;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sector = ((bearingDegrees % 360) / 45).round() % 8;
    final direction = const [
      'N',
      'NE',
      'E',
      'SE',
      'S',
      'SW',
      'W',
      'NW',
    ][sector];
    final warmth = TreasureAreaSnapshot.warmth(distanceMiles);
    final color = Color.lerp(
      Colors.blue,
      Colors.orange,
      TreasureAreaSnapshot.heat(distanceMiles),
    )!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 196,
          height: 196,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.surfaceContainerHighest,
            border: Border.all(color: color, width: 3),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned(top: 10, child: Text('N')),
              const Positioned(right: 12, child: Text('E')),
              const Positioned(bottom: 10, child: Text('S')),
              const Positioned(left: 12, child: Text('W')),
              Transform.rotate(
                angle: sector * math.pi / 4,
                child: Icon(Icons.navigation, size: 100, color: color),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          distanceMiles <= 1
              ? 'Hot - explore this general area'
              : 'Head $direction - $warmth',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text('North-up compass'),
        const SizedBox(height: 8),
        SizedBox(
          width: 240,
          child: Semantics(
            label: '$warmth, approximate area proximity',
            child: LinearProgressIndicator(
              value: TreasureAreaSnapshot.heat(distanceMiles),
              minHeight: 10,
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(
          width: 240,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text('Cold / farther')),
              Expanded(child: Text('Hot / closer', textAlign: TextAlign.end)),
            ],
          ),
        ),
      ],
    );
  }
}
