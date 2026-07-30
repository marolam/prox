import "package:flutter/material.dart";
import "package:prox/widgets/placeholder_route_screen.dart";

class AppReviewSurvivalKitScreen extends StatelessWidget {
  const AppReviewSurvivalKitScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderRouteScreen(
        title: "App Review survival kit",
        message: "Tester account notes, review steps, and checklist content will appear here.",
        icon: Icons.verified_outlined,
      );
}