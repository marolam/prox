import "package:flutter/material.dart";
import "package:prox/models/notification_item.dart";

class NotificationDestination {
  const NotificationDestination(this.route, [this.arguments]);
  final String route;
  final Map<String, String>? arguments;
}

class NotificationRouter {
  NotificationRouter._();

  static final NotificationRouter instance = NotificationRouter._();

  NotificationDestination destinationFor(NotificationItem item) {
    final type = item.type.trim().toLowerCase();
    String id(Object? raw) {
      if (raw is! String) return '';
      final value = raw.trim();
      return value.isNotEmpty && value.length <= 512 && !value.contains('/')
          ? value
          : '';
    }

    final chatId = id(
      item.chatId ?? item.data['chatId'] ?? item.data['meetupId'],
    );
    final otherUid = id(
      item.data['otherUid'] ?? item.data['senderUid'] ?? item.data['fromUid'],
    );
    final hasParticipant = chatId.isNotEmpty && otherUid.isNotEmpty;
    final args = <String, String>{'chatId': chatId, 'otherUid': otherUid};
    if (type.contains("message") || type.contains("chat")) {
      return hasParticipant
          ? NotificationDestination('/chat', args)
          : const NotificationDestination('/inbox');
    }
    if (type.startsWith('meetup')) {
      if (!hasParticipant) return const NotificationDestination('/meetups');
      final status = (item.data['status'] ?? '').toString().toLowerCase();
      return NotificationDestination(
        const {'arrived', 'live', 'on_my_way', 'running_late'}.contains(status)
            ? '/meetup_live'
            : '/meetup_plan',
        args,
      );
    }
    if (type.contains('match')) return const NotificationDestination('/nearby');
    return const NotificationDestination('/home');
  }

  void handleTap(BuildContext context, NotificationItem item) {
    final destination = destinationFor(item);
    Navigator.of(
      context,
    ).pushNamed(destination.route, arguments: destination.arguments);
  }
}
