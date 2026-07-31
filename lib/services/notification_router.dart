import "package:flutter/material.dart";
import "package:prox/models/notification_item.dart";

class NotificationRouter {
  NotificationRouter._();

  static final NotificationRouter instance = NotificationRouter._();

  void handleTap(BuildContext context, NotificationItem item) {
    final type = item.type.trim().toLowerCase();
    if (type.contains("message") || type.contains("chat")) {
      Navigator.of(context).pushNamed("/chats");
    } else if (type == "meetup") {
      Navigator.of(context).pushNamed("/meetup");
    } else {
      Navigator.of(context).pushNamed("/home");
    }
  }
}