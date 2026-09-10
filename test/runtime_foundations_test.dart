import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:prox/models/notification_item.dart";
import "package:prox/services/app_lifecycle_service.dart";
import "package:prox/services/ime_visibility_service.dart";
import "package:prox/services/notification_feed_service.dart";
import "package:prox/services/user_settings_service.dart";
import "package:prox/utils/bounded_async_map.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("background and foreground changes pause and resume services", (tester) async {
    final service = AppLifecycleService.instance;
    service.ensureStarted();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(service.isForeground, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(service.isForeground, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(service.isForeground, isTrue);
  });

  testWidgets("keyboard observer follows real view insets", (tester) async {
    final service = ImeVisibilityService.instance;
    service.ensureStarted();
    addTearDown(tester.view.resetViewInsets);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    expect(service.isVisible, isTrue);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    expect(service.isVisible, isFalse);
  });

  test("concurrent settings loads wait and notify with saved values", () async {
    SharedPreferences.setMockInitialValues({
      "user_settings": jsonEncode({"textScaleFactor": 1.4}),
    });
    final service = UserSettingsService.instance;
    final events = <double>[];
    final sub = service.watch().listen((settings) => events.add(settings.textScaleFactor));
    final first = service.ensureLoaded();
    final second = service.ensureLoaded();
    await Future.wait([first, second]);
    await Future<void>.delayed(Duration.zero);
    expect(service.current.textScaleFactor, 1.4);
    expect(events, contains(1.4));
    await sub.cancel();
  });

  test("bounded work limits concurrency and retains completion order", () async {
    var active = 0;
    var peak = 0;
    final output = await boundedAsyncMap(List.generate(12, (i) => i), (i) async {
      active++;
      if (active > peak) peak = active;
      await Future<void>.delayed(Duration(milliseconds: 12 - i));
      active--;
      return i * 2;
    }, concurrency: 3);
    expect(peak, 3);
    expect(output, List.generate(12, (i) => i * 2));
  });

  test("duplicate push messages do not resurrect unread state or grow without bound", () {
    final service = NotificationFeedService.instance;
    service.clear();
    NotificationItem item(String id) => NotificationItem(id: id, type: "chat",
      title: "Message", body: "A message arrived", createdAtUtc: DateTime.utc(2026), seen: false);
    service.add(item("one"));
    service.markSeen("one");
    service.add(item("one"));
    expect(service.current.length, 1);
    expect(service.current.single.seen, isTrue);
    for (var i = 0; i < 300; i++) { service.add(item("message-$i")); }
    expect(service.current.length, NotificationFeedService.maximumItems);
    service.clear();
    expect(service.current, isEmpty);
  });
}
