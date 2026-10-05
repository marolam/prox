import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:prox/screens/settings/business_avatar_settings_screen.dart";
import "package:prox/services/business_mode/business_avatar_settings_service.dart";

class _FakeBusinessAvatarSettingsStore implements BusinessAvatarSettingsStore {
  _FakeBusinessAvatarSettingsStore({
    required this.initial,
  });

  final BusinessAvatarSettings initial;
  int loadCalls = 0;
  int saveCalls = 0;
  bool? lastEnabled;
  String? lastReply;

  @override
  Future<BusinessAvatarSettings> loadForCurrentUser() async {
    loadCalls += 1;
    return initial;
  }

  @override
  Future<void> saveForCurrentUser({
    required bool enabled,
    required String reply,
  }) async {
    saveCalls += 1;
    lastEnabled = enabled;
    lastReply = reply;
  }
}

void main() {
  testWidgets("loads persisted business avatar settings and saves updates", (
    tester,
  ) async {
    final store = _FakeBusinessAvatarSettingsStore(
      initial: const BusinessAvatarSettings(
        enabled: true,
        reply: "Initial reply",
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BusinessAvatarSettingsScreen(settingsStore: store),
      ),
    );
    await tester.pumpAndSettle();

    expect(store.loadCalls, 1);
    expect(find.text("Business avatar reply"), findsWidgets);
    expect(find.text("Initial reply"), findsNWidgets(2));
    expect(find.text("Enable business avatar reply"), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();

    await tester.enterText(find.byType(TextField), "Updated reply");
    await tester.tap(find.widgetWithText(FilledButton, "Save"));
    await tester.pumpAndSettle();

    expect(store.saveCalls, 1);
    expect(store.lastEnabled, false);
    expect(store.lastReply, "Updated reply");
    expect(find.text("Business avatar reply saved."), findsOneWidget);
  });
}
