import "package:flutter/material.dart";
import "package:prox/widgets/placeholder_route_screen.dart";

class MatchScopeSettingsScreen extends StatelessWidget {
  const MatchScopeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderRouteScreen(
        title: "Match settings",
        message: "Match scope, tree depth, and distance precision settings will appear here.",
        icon: Icons.tune,
      );
}