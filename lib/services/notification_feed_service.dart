import "dart:async";

import "package:prox/models/notification_item.dart";

class NotificationFeedService {
  NotificationFeedService._();
  static final NotificationFeedService instance = NotificationFeedService._();

  final StreamController<List<NotificationItem>> _controller =
      StreamController<List<NotificationItem>>.broadcast();
  final List<NotificationItem> _items = <NotificationItem>[];
  static const int maximumItems = 200;

  Stream<List<NotificationItem>> watch() => _controller.stream;

  List<NotificationItem> get current =>
      List<NotificationItem>.unmodifiable(_items);

  void add(NotificationItem item) {
    // FCM can redeliver a message or expose it via both foreground and tap APIs.
    final existing = _items.where((entry) => entry.id == item.id).firstOrNull;
    if (existing != null && existing.seen && !item.seen) return;
    _items.removeWhere((entry) => entry.id == item.id);
    _items.insert(0, item);
    if (_items.length > maximumItems) _items.removeRange(maximumItems, _items.length);
    if (!_controller.isClosed) {
      _controller.add(current);
    }
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    if (!_controller.isClosed) _controller.add(current);
  }

  void markSeen(String id) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0 || _items[index].seen) return;
    final item = _items[index];
    _items[index] = NotificationItem(
      id: item.id,
      type: item.type,
      title: item.title,
      body: item.body,
      createdAtUtc: item.createdAtUtc,
      seen: true,
      chatId: item.chatId,
      data: item.data,
    );
    if (!_controller.isClosed) _controller.add(current);
  }

  void markAllSeen() {
    var changed = false;
    for (var i = 0; i < _items.length; i += 1) {
      final item = _items[i];
      if (item.seen) continue;
      changed = true;
      _items[i] = NotificationItem(
        id: item.id,
        type: item.type,
        title: item.title,
        body: item.body,
        createdAtUtc: item.createdAtUtc,
        seen: true,
        chatId: item.chatId,
        data: item.data,
      );
    }
    if (changed && !_controller.isClosed) _controller.add(current);
  }
}
