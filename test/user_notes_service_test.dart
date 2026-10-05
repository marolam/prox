import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/user_notes_service.dart';

void main() {
  test(
    'local notes stream emits saved text without a Firestore listener',
    () async {
      final service = UserNotesService.forTesting(uidProvider: () => 'owner');
      final values = <String>[];
      final stream = service.watchNote(otherUid: 'peer');
      expect(identical(stream, service.watchNote(otherUid: 'peer')), isTrue);
      final subscription = stream.listen(values.add);
      await Future<void>.delayed(Duration.zero);
      await service.setNote(otherUid: 'peer', text: 'Meet next week');
      await service.setNote(otherUid: 'someone-else', text: 'Unrelated');
      await Future<void>.delayed(Duration.zero);
      expect(values, ['', 'Meet next week']);
      expect(await service.getNoteText(otherUid: 'peer'), 'Meet next week');
      await subscription.cancel();
    },
  );

  test('notes are scoped to the signed-in account', () async {
    var owner = 'first';
    final service = UserNotesService.forTesting(uidProvider: () => owner);
    await service.setNote(otherUid: 'peer', text: 'Private');
    owner = 'second';
    expect(await service.getNoteText(otherUid: 'peer'), isEmpty);
    expect(await service.watchNote(otherUid: 'peer').first, isEmpty);
    owner = '';
    await service.setNote(otherUid: 'peer', text: 'Signed out');
    expect(await service.getNoteText(otherUid: 'peer'), isEmpty);
    owner = 'first';
    expect(await service.getNoteText(otherUid: 'peer'), 'Private');
  });
}
