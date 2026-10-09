import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/party_connection_service.dart';
import 'package:prox/services/party_service.dart';

void main() {
  test(
    'live code exchange cannot appear as a remotely acceptable Party request',
    () {
      final record = <String, dynamic>{
        'members': ['alice', 'bob'],
        'status': 'pending',
        'decisions': {'alice': 'add'},
        'proof': {'kind': 'inPersonCode'},
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(minutes: 3)),
        ),
      };
      expect(PendingPartyConnection.fromMap(record, 'bob'), isNull);
      record['proof'] = {'kind': 'completedMeetup', 'chatId': 'meetup'};
      expect(
        PendingPartyConnection.fromMap(record, 'bob')?.theirDecision,
        'add',
      );
    },
  );

  test('unproven legacy Party documents do not claim confirmed membership', () {
    expect(PartyMemberEntry.fromDoc('bob', {'mutual': true}).mutual, false);
    expect(
      PartyMemberEntry.fromDoc('bob', {
        'mutual': true,
        'metInPerson': true,
      }).mutual,
      true,
    );
  });
}
