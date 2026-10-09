import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/widgets/matching_scope_picker.dart';

void main() {
  testWidgets('Party and Tree stay available while Public is locked', (
    tester,
  ) async {
    final selected = <MatchPartyScope>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchingScopePicker(
            scope: MatchPartyScope.public,
            publicUnlocked: false,
            onChanged: selected.add,
          ),
        ),
      ),
    );
    final tree = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Party + Tree'),
    );
    expect(tree.selected, isTrue);
    final public = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Public · Locked'),
    );
    expect(public.onSelected, isNull);
    await tester.tap(find.text('Party Only'));
    await tester.tap(find.text('Party + Tree'));
    expect(selected, [MatchPartyScope.partyOnly, MatchPartyScope.tree]);
  });

  testWidgets('Public unlock keeps the private scope choices available', (
    tester,
  ) async {
    final selected = <MatchPartyScope>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchingScopePicker(
            scope: MatchPartyScope.tree,
            publicUnlocked: true,
            onChanged: selected.add,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Public'));
    await tester.tap(find.text('Party Only'));
    await tester.tap(find.text('Party + Tree'));
    expect(selected, [
      MatchPartyScope.public,
      MatchPartyScope.partyOnly,
      MatchPartyScope.tree,
    ]);
  });
}
