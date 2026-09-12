import "package:flutter_test/flutter_test.dart";

import "package:prox/models/notification_item.dart";
import "package:prox/services/notification_feed_service.dart";

void main() {
  test("dismissed notification is marked seen", () {
    final service = NotificationFeedService.instance;
    const id = "meetup-dismiss-regression";
    service.add(
      NotificationItem(
        id: id,
        type: "meetup",
        title: "Meetup update",
        body: "Status changed",
        createdAtUtc: DateTime.utc(2026, 8, 30),
        seen: false,
      ),
    );

    service.markSeen(id);

    expect(service.current.firstWhere((item) => item.id == id).seen, isTrue);
  });

  test("opening the notification feed clears all unread items", () {
    final service = NotificationFeedService.instance;
    service.add(
      NotificationItem(
        id: "meetup-clear-all-regression",
        type: "meetup",
        title: "Meetup update",
        body: "Status changed again",
        createdAtUtc: DateTime.utc(2026, 8, 30, 1),
        seen: false,
      ),
    );

    service.markAllSeen();

    expect(service.current.where((item) => !item.seen), isEmpty);
  });
}
