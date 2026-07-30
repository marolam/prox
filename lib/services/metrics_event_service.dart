class MetricsEventService {
  MetricsEventService._();
  static final MetricsEventService instance = MetricsEventService._();

  Future<void> log(
    String event, {
    Map<String, Object?>? meta,
    String category = "",
    String contextId = "",
    String contextType = "",
  }) async {}
}
