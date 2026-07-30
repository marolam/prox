import "package:flutter/material.dart";
import "package:prox/widgets/placeholder_route_screen.dart";

class DevPanel extends StatelessWidget {
  const DevPanel({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderRouteScreen(title: "Dev panel", message: "Dev panel placeholder.");
}