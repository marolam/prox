import 'package:flutter/painting.dart';

/// Apply the in-app preference after the OS scaler has sized each font. This
/// preserves nonlinear accessibility scaling instead of replacing it with 1x.
class AppTextScaler extends TextScaler {
  const AppTextScaler({required this.systemScaler, required this.preference});
  final TextScaler systemScaler;
  final double preference;

  double get _factor => preference.isFinite ? preference.clamp(0.9, 1.6) : 1;

  @override
  double scale(double fontSize) => systemScaler.scale(fontSize) * _factor;

  @override
  double get textScaleFactor => systemScaler.textScaleFactor * _factor;

  @override
  bool operator ==(Object other) =>
      other is AppTextScaler &&
      other.systemScaler == systemScaler &&
      other.preference == preference;
  @override
  int get hashCode => Object.hash(systemScaler, preference);
}
