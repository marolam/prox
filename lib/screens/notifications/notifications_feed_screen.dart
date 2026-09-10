import "package:flutter/material.dart";
import "package:prox/models/notification_item.dart";
import "package:prox/services/notification_feed_service.dart";
import "package:prox/services/notification_router.dart";

class NotificationsFeedScreen extends StatelessWidget {
  const NotificationsFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = NotificationFeedService.instance;
    WidgetsBinding.instance.addPostFrameCallback((_) => service.markAllSeen());

    return Scaffold(
      appBar: AppBar(title: const Text("Notifications")),
      body: StreamBuilder<List<NotificationItem>>(
        stream: service.watch(),
        initialData: service.current,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <NotificationItem>[];
          if (items.isEmpty) {
            return const Center(child: Text("No notifications yet."));
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: Icon(
                  item.type == "meetup"
                      ? Icons.handshake_outlined
                      : Icons.notifications_outlined,
                ),
                title: Text(item.title),
                subtitle: Text(item.body),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  service.markSeen(item.id);
                  NotificationRouter.instance.handleTap(context, item);
                },
              );
            },
          );
        },
      ),
    );
  }
}
