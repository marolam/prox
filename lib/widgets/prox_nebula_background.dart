import "package:flutter/material.dart";

class ProxNebulaBackground extends StatelessWidget {
  const ProxNebulaBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0B1020)],
        ),
      ),
      child: child,
    );
  }
}
