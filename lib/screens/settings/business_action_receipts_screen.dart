import "package:flutter/material.dart";
import "package:prox/widgets/placeholder_route_screen.dart";

class BusinessActionReceiptsScreen extends StatelessWidget {
  const BusinessActionReceiptsScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderRouteScreen(
        title: "Business receipts",
        message: "Business action confirmations logged on this device will appear here.",
        icon: Icons.receipt_long_outlined,
      );
}