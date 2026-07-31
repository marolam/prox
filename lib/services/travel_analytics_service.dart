class TravelAnalyticsService {
  TravelAnalyticsService._();

  static final TravelAnalyticsService instance = TravelAnalyticsService._();

  void handleSample({
    Object? sample,
    DateTime? ts,
    bool isTraveling = false,
    Map<String, Object?> data = const <String, Object?>{},
  }) {}
}