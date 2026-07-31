import "package:flutter/material.dart";
import "package:prox/widgets/placeholder_route_screen.dart";

class TrustRulesScreen extends StatelessWidget {
  const TrustRulesScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderRouteScreen(
        title: "Trust rulebook",
        message: "Readable trust rules and explanations will appear here.",
        icon: Icons.menu_book_outlined,
      );
}