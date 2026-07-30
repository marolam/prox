enum NotificationCopyKey { match, message, meetup, party, system }

class NotificationCopy {
  static String title(NotificationCopyKey key) {
    switch (key) {
      case NotificationCopyKey.match:
        return "New match";
      case NotificationCopyKey.message:
        return "New message";
      case NotificationCopyKey.meetup:
        return "Meetup update";
      case NotificationCopyKey.party:
        return "Party update";
      case NotificationCopyKey.system:
        return "Prox";
    }
  }

  static String body(NotificationCopyKey key) => "Tap to open.";
}