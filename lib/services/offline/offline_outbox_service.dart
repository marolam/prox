class OfflineOutboxService {
  OfflineOutboxService._();
  static final OfflineOutboxService instance = OfflineOutboxService._();

  Future<void> start() async {}

  Future<void> enqueueSet({
    required String docPath,
    required Map<String, Object?> data,
    String? idempotencyKey,
  }) async {}

  Future<void> enqueueConfirmArrival({
    required String meetupId,
    required String uid,
  }) async {}
}
