class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAtUtc,
    required this.seen,
    this.chatId,
    this.data = const <String, dynamic>{},
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime createdAtUtc;
  final bool seen;
  final String? chatId;
  final Map<String, dynamic> data;
}
