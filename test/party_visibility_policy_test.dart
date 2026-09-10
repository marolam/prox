import "dart:io";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter_test/flutter_test.dart";
import "package:prox/screens/party/party_list_screen.dart";
import "package:prox/services/party_service.dart";

void main() {
  group("Party visibility policy", () {
    test("shows only users explicitly added to the canonical party", () {
      final visible = PartyListScreen.visibleRelationshipUids(
        myUid: "me",
        partyUids: const <String>["party_a", " party_b "],
        referredByMeUids: const <String>["ref_by_me"],
        referredMeUids: const <String>["ref_me"],
        incomingRequestUids: const <String>[],
        outgoingRequestUids: const <String>[],
      );

      expect(
        visible,
        <String>{"party_a", "party_b"},
      );
      expect(visible.contains("random_firebase_user"), isFalse);
      expect(visible.contains("plain_referral_signup"), isFalse);
    });

    test("never includes the current user or blank ids", () {
      final visible = PartyListScreen.visibleRelationshipUids(
        myUid: "me",
        partyUids: const <String>["me", ""],
        referredByMeUids: const <String>[" me "],
        referredMeUids: const <String>["other", "   "],
        incomingRequestUids: const <String>["incoming"],
        outgoingRequestUids: const <String>["outgoing"],
      );

      expect(visible, isEmpty);
    });

    test("only in-person Party referrals become Party candidates", () {
      expect(
        PartyListScreen.inPersonPartyReferralUid(
          docId: "plain_referral_signup",
          data: const <String, dynamic>{"uid": "plain_referral_signup"},
        ),
        isNull,
      );
      expect(
        PartyListScreen.inPersonPartyReferralUid(
          docId: "fallback_uid",
          data: const <String, dynamic>{"partyInPersonQrRequested": true},
        ),
        "fallback_uid",
      );
      expect(
        PartyListScreen.inPersonPartyReferralUid(
          docId: "doc_uid",
          data: const <String, dynamic>{
            "partyInPersonQrRequested": true,
            "uid": " data_uid ",
          },
        ),
        "data_uid",
      );
    });

    test("only other in-person Party referrers become Party candidates", () {
      expect(
        PartyListScreen.inPersonPartyReferrerUid(
          referrerUid: "referrer",
          myUid: "me",
          data: const <String, dynamic>{"partyInPersonQrRequested": true},
        ),
        "referrer",
      );
      expect(
        PartyListScreen.inPersonPartyReferrerUid(
          referrerUid: "plain_referrer",
          myUid: "me",
          data: const <String, dynamic>{},
        ),
        isNull,
      );
      expect(
        PartyListScreen.inPersonPartyReferrerUid(
          referrerUid: "me",
          myUid: "me",
          data: const <String, dynamic>{"partyInPersonQrRequested": true},
        ),
        isNull,
      );
    });

    test("online presence must be fresh and unexpired", () {
      final now = DateTime(2026, 8, 27, 12);
      expect(
        PartyService.isOnlinePresenceData(<String, dynamic>{
          "ts": Timestamp.fromDate(now.subtract(const Duration(minutes: 2))),
          "expiresAt": Timestamp.fromDate(now.add(const Duration(minutes: 2))),
        }, now: now),
        isTrue,
      );
      expect(
        PartyService.isOnlinePresenceData(<String, dynamic>{
          "ts": Timestamp.fromDate(now.subtract(const Duration(minutes: 6))),
          "expiresAt": Timestamp.fromDate(now.add(const Duration(minutes: 2))),
        }, now: now),
        isFalse,
      );
    });

    test("Party UI sorts presence and keeps offline messaging available", () {
      final party =
          File("lib/screens/party/party_list_screen.dart").readAsStringSync();
      final meetups =
          File("lib/services/meetup_service.dart").readAsStringSync();

      expect(party, contains("watchOnlinePartyUids"));
      expect(party, contains('value: "message"'));
      expect(party, contains("enabled: online"));
      expect(party, contains("Hot now"));
      expect(party, contains("New requests"));
      expect(meetups, contains("recipient_offline"));
    });
  });
}
