import "package:flutter/material.dart";
import "package:prox/widgets/placeholder_route_screen.dart";

class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderRouteScreen(
        title: "Blocked users",
        message: "Meetup-request blocks managed on this device will appear here.",
        icon: Icons.block_outlined,
      );
}