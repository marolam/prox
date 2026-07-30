import "package:flutter/material.dart";
import "package:prox/widgets/placeholder_route_screen.dart";

class BusinessAvatarSettingsScreen extends StatelessWidget {
  const BusinessAvatarSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderRouteScreen(
        title: "Business avatar message",
        message: "Business avatar messaging is coming soon.",
        icon: Icons.smart_toy_outlined,
      );
}