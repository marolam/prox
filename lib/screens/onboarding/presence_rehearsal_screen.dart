import "package:flutter/material.dart";
import "package:prox/widgets/placeholder_route_screen.dart";

class PresenceRehearsalScreen extends StatelessWidget {
  const PresenceRehearsalScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) => const PlaceholderRouteScreen(title: "Presence rehearsal", message: "Presence setup placeholder.");
}