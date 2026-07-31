/// lib/screens/services/match_events_service.dart
///
/// Local-only event list used for subtle scoring (reciprocity/trust heuristics).
///
/// Compatibility:
/// - Some screens expect ensureLoaded(), clear()
/// - Some screens expect MatchEvent.distanceMiles + tsMs getters
class MatchEvent {
  final String otherUid;
  final DateTime ts;
  final String mode;
  final List<String> sharedKeywords;
  final double? centerLat;
  final double? centerLon;

  /// Optional, UI-only.
  final double? _distanceMiles;

  const MatchEvent({
    required this.otherUid,
    required this.ts,
    this.mode = "normal",
    this.sharedKeywords = const <String>[],
    this.centerLat,
    this.centerLon,
    double? distanceMiles,
  }) : _distanceMiles = distanceMiles;

  double get distanceMiles => _distanceMiles ?? 0.0;
  int get tsMs => ts.millisecondsSinceEpoch;
}

class MatchEventsService {
  MatchEventsService._();
  static final MatchEventsService instance = MatchEventsService._();

  final List<MatchEvent> _events = <MatchEvent>[];

  /// Compatibility no-op. (Future hook for persistence if needed.)
  Future<void> ensureLoaded() async {
    return;
  }

  void clear() {
    _events.clear();
  }

  void addEvent(
    String otherUid, {
    double? distanceMiles,
    String mode = "normal",
    List<String> sharedKeywords = const <String>[],
    double? centerLat,
    double? centerLon,
  }) {
    final u = otherUid.trim();
    if (u.isEmpty) return;
    _events.insert(
      0,
      MatchEvent(
        otherUid: u,
        ts: DateTime.now(),
        mode: mode,
        sharedKeywords: sharedKeywords,
        centerLat: centerLat,
        centerLon: centerLon,
        distanceMiles: distanceMiles,
      ),
    );
    if (_events.length > 200) {
      _events.removeRange(200, _events.length);
    }
  }

  List<MatchEvent> readEvents() => List<MatchEvent>.unmodifiable(_events);
}
