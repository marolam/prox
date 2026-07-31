import "package:flutter/material.dart";

class ProxMotion {
  static const Duration kFast = Duration(milliseconds: 180);

  static bool prefersReducedMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration dur(BuildContext context, Duration duration) => prefersReducedMotion(context) ? Duration.zero : duration;

  static Curve curve(BuildContext context) => Curves.easeOutCubic;
}