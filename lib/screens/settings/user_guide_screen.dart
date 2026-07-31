import "package:flutter/material.dart";
import "package:prox/widgets/placeholder_route_screen.dart";

class UserGuideScreen extends StatelessWidget {
  const UserGuideScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderRouteScreen(
        title: "User's Guide",
        message: "Feature guide and quick entry points will appear here.",
        icon: Icons.menu_book_outlined,
      );
}