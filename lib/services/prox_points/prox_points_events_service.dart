class ProxPointsEventsService {
  ProxPointsEventsService._();

  static final ProxPointsEventsService instance = ProxPointsEventsService._();

  Future<void> log({
    required String kind,
    required String title,
    required int delta,
    String meta = "",
  }) async {}
}