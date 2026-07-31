import "package:flutter/material.dart";
import "package:prox/widgets/placeholder_route_screen.dart";

class MyIncidentsScreen extends StatelessWidget {
  const MyIncidentsScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderRouteScreen(
        title: "My reports & appeals",
        message: "Incident drafts, submissions, and appeal decisions will appear here.",
        icon: Icons.gavel_outlined,
      );
}