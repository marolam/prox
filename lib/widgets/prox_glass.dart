import "dart:ui";

import "package:flutter/material.dart";

class ProxGlass extends StatelessWidget {
  const ProxGlass({
    super.key,
    required this.child,
    this.radius = 16,
    this.blurSigma = 16,
    this.fillOpacity = 0.12,
    this.borderOpacity = 0.2,
    this.padding,
  });

  final Widget child;
  final double radius;
  final double blurSigma;
  final double fillOpacity;
  final double borderOpacity;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: fillOpacity),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: cs.outline.withValues(alpha: borderOpacity)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class ProxGlassCard extends StatelessWidget {
  const ProxGlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.highlight,
    this.glow,
    this.padding,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? highlight;
  final Color? glow;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final tint = highlight ?? Theme.of(context).colorScheme.primary;
    return ProxGlass(
      padding: padding,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tint.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: (glow ?? tint).withValues(alpha: 0.16),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class ProxGlassButton extends StatelessWidget {
  const ProxGlassButton({
    super.key,
    required this.label,
    required this.onTap,
    this.highlight,
  });

  final String label;
  final VoidCallback onTap;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: onTap,
        child: Text(label),
      ),
    );
  }
}
