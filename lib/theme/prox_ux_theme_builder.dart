import "package:flutter/material.dart";
import "package:prox/models/user_settings.dart";

class ProxUxThemeBuilder {
  static ThemeData buildFor(UserSettings settings) {
    final seed = settings.uxMode == AppUxMode.business
        ? const Color(0xFF7C3AED)
        : const Color(0xFF14B8A6);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
    );
  }
}
