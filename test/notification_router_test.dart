import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/models/notification_item.dart';
import 'package:prox/services/notification_router.dart';
import 'package:prox/services/notification_feed_service.dart';
import 'package:prox/screens/notifications/notifications_feed_screen.dart';

NotificationItem item(String type, [Map<String, dynamic> data = const {}]) =>
    NotificationItem(
      id: 'notification',
      type: type,
      title: 'New activity',
      body: 'Open this activity',
      createdAtUtc: DateTime.utc(2026),
      seen: false,
      data: data,
    );

void main() {
  final router = NotificationRouter.instance;
  test('notification types use registered inbox/history/matching routes', () {
    for (final type in [
      'message',
      'chat_request',
      'party_message',
      'party_chat_request',
    ]) {
      expect(router.destinationFor(item(type)).route, '/inbox');
    }
    expect(router.destinationFor(item('meetup')).route, '/meetups');
    expect(router.destinationFor(item('match')).route, '/nearby');
    expect(router.destinationFor(item('party_request')).route, '/party');
    expect(router.destinationFor(item('announcement')).route, '/home');
  });

  test('full notification context opens the correct chat or live meetup', () {
    final message = router.destinationFor(
      item('message', {'chatId': 'pair', 'senderUid': 'other'}),
    );
    expect(message.route, '/chat');
    expect(message.arguments, {'chatId': 'pair', 'otherUid': 'other'});
    final live = router.destinationFor(
      item('meetup', {
        'meetupId': 'pair',
        'otherUid': 'other',
        'status': 'arrived',
      }),
    );
    expect(live.route, '/meetup_live');
    expect(live.arguments, {'chatId': 'pair', 'otherUid': 'other'});
    expect(
      router
          .destinationFor(
            item('meetup', {
              'chatId': 'pair',
              'otherUid': 'other',
              'status': 'accepted',
            }),
          )
          .route,
      '/meetup_plan',
    );
  });

  test('malformed or incomplete IDs never open a broken detail screen', () {
    for (final data in [
      {'chatId': 'pair'},
      {'chatId': 'collection/pair', 'otherUid': 'other'},
      {'chatId': 'pair', 'otherUid': <String>[]},
    ]) {
      expect(router.destinationFor(item('message', data)).route, '/inbox');
    }
  });

  testWidgets('feed notification is actionable and opens its destination', (
    tester,
  ) async {
    NotificationFeedService.instance.clear();
    NotificationFeedService.instance.add(
      item('message', {'chatId': 'pair', 'otherUid': 'other'}),
    );
    RouteSettings? pushed;
    await tester.pumpWidget(
      MaterialApp(
        home: const NotificationsFeedScreen(),
        onGenerateRoute: (settings) {
          pushed = settings;
          return MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Conversation')),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New activity'));
    await tester.pumpAndSettle();
    expect(pushed?.name, '/chat');
    expect(pushed?.arguments, {'chatId': 'pair', 'otherUid': 'other'});
    expect(find.text('Conversation'), findsOneWidget);
    NotificationFeedService.instance.clear();
  });
}
