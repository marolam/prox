import "package:flutter/material.dart";
import "package:prox/widgets/placeholder_route_screen.dart";

class CosmeticsScreen extends StatelessWidget {
  const CosmeticsScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderRouteScreen(
        title: "Cosmetics",
        message: "Themes and UI flair settings will appear here.",
        icon: Icons.palette_outlined,
      );
}