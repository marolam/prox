import "package:flutter/material.dart";
import "package:prox/widgets/placeholder_route_screen.dart";

class TrustTimelineScreen extends StatelessWidget {
  const TrustTimelineScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderRouteScreen(
        title: "Trust timeline",
        message: "A timeline of events affecting trust will appear here.",
        icon: Icons.timeline,
      );
}