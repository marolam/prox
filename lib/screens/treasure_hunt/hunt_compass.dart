import 'package:flutter/material.dart';
import 'dart:math' as math;

// Removed: import 'dart:math'; // unused



/// Very lightweight compass-like indicator used in Treasure Hunt mode.

class HuntCompass extends StatelessWidget {

  final double bearingDegrees; // 0..360



  const HuntCompass({super.key, required this.bearingDegrees});



  @override

  Widget build(BuildContext context) {

    final scheme = Theme.of(context).colorScheme;



    return AspectRatio(

      aspectRatio: 1,

      child: Container(

        decoration: BoxDecoration(

          color: scheme.surfaceContainerHighest,

          shape: BoxShape.circle,

          border: Border.all(color: scheme.outlineVariant),

        ),

        alignment: Alignment.center,

        child: Column(

          mainAxisAlignment: MainAxisAlignment.center,

          children: [

            Transform.rotate(
              angle: bearingDegrees * math.pi / 180.0,
              child: Icon(Icons.navigation, size: 48, color: scheme.primary),
            ),

            const SizedBox(height: 8),

            Text(

              '${bearingDegrees.toStringAsFixed(0)} deg',

              style: Theme.of(context).textTheme.titleLarge,

            ),

            const SizedBox(height: 4),

            Text(

              'Point and walk',

              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),

            )

          ],

        ),

      ),

    );

  }

}




