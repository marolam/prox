import "package:flutter/material.dart";
import "package:prox/widgets/placeholder_route_screen.dart";

class CreatorPanelScreen extends StatelessWidget {
  const CreatorPanelScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderRouteScreen(
        title: "Creator panel",
        message: "Creator tools will appear here.",
        icon: Icons.dashboard_customize_outlined,
      );
}