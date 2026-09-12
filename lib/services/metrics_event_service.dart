import "package:prox/services/ui_telemetry_service.dart";

/// Local operational counts, excluding user payloads and external analytics.
class MetricsEventService {
  MetricsEventService._();
  static final MetricsEventService instance = MetricsEventService._();

  Future<void> log(
    String event, {
    Map<String, Object?>? meta,
    String category = "",
    String contextId = "",
    String contextType = "",
  }) async {
    if (event.isEmpty || event.length > 100) return;
    UiTelemetryService.instance.log(event);
  }
}
