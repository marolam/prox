import "dart:async";

import "package:prox/models/notification_item.dart";

class NotificationFeedService {
  NotificationFeedService._();
  static final NotificationFeedService instance = NotificationFeedService._();

  final StreamController<List<NotificationItem>> _controller =
      StreamController<List<NotificationItem>>.broadcast();
  final List<NotificationItem> _items = <NotificationItem>[];

  Stream<List<NotificationItem>> watch() => _controller.stream;

  List<NotificationItem> get current => List<NotificationItem>.unmodifiable(_items);

  void add(NotificationItem item) {
    _items.insert(0, item);
    if (!_controller.isClosed) {
      _controller.add(current);
    }
  }
}
