import "package:flutter/material.dart";

class LocationDisclosureScreen extends StatelessWidget {
  const LocationDisclosureScreen({super.key, this.showAppBar = false});

  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final body = ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        Text(
          "Location & privacy",
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 12),
        Text(
          "Prox uses location to power nearby discovery and meetup confirmation. Exact coordinates are not shown to other users.",
        ),
      ],
    );
    if (!showAppBar) return body;
    return Scaffold(appBar: AppBar(title: const Text("Location & privacy")), body: body);
  }
}