class ProxDistanceFormat {
  static String? bucketMilesOrNull(double? miles) {
    if (miles == null || miles.isNaN || miles.isInfinite || miles < 0) {
      return null;
    }
    if (miles < 0.1) return "Very close";
    if (miles < 1) return "${(miles * 5280).round()} ft";
    if (miles < 10) return "${miles.toStringAsFixed(1)} mi";
    return "${miles.round()} mi";
  }
}