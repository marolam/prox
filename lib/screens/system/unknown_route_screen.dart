import "package:flutter/material.dart";

class UnknownRouteScreen extends StatelessWidget {
  const UnknownRouteScreen({super.key, this.name});

  final String? name;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text("Page unavailable")),
        body: Center(child: Text("Unknown route: ${name ?? "unnamed"}")),
      );
}