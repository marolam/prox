import "package:prox/services/ui_telemetry_service.dart";

/// Local interaction counters; authoritative trust comes from server receipts.
class ReciprocityService {
  ReciprocityService._();
  static final ReciprocityService instance = ReciprocityService._();

  void recordMeetupCompleted(String otherUid) => _record(otherUid, "meetup_completed");
  void recordIncomingMessage(String otherUid) => _record(otherUid, "message_received");
  void recordThumbGiven(String otherUid) => _record(otherUid, "rating_submitted");
  void _record(String uid, String event) {
    if (uid.trim().isNotEmpty) UiTelemetryService.instance.log(event);
  }
}
