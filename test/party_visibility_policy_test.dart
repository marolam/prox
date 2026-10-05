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

      expect(visible, <String>{"party_a", "party_b"});
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
          documentPath: "users/me/referrals/plain_referral_signup",
          data: const <String, dynamic>{"uid": "plain_referral_signup"},
          myUid: "me",
        ),
        isNull,
      );
      expect(
        PartyListScreen.inPersonPartyReferralUid(
          documentPath: "users/me/referrals/fallback_uid",
          data: const <String, dynamic>{
            "partyInPersonQrRequested": true,
            "inPersonVerified": true,
          },
          myUid: "me",
        ),
        "fallback_uid",
      );
      expect(
        PartyListScreen.inPersonPartyReferralUid(
          documentPath: "users/me/referrals/doc_uid",
          data: const <String, dynamic>{
            "partyInPersonQrRequested": true,
            "inPersonVerified": true,
            "uid": " data_uid ",
          },
          myUid: "me",
        ),
        isNull,
      );
    });

    test("only other in-person Party referrers become Party candidates", () {
      expect(
        PartyListScreen.inPersonPartyReferrerUid(
          documentPath: "users/referrer/referrals/me",
          myUid: "me",
          data: const <String, dynamic>{
            "uid": "me",
            "partyInPersonQrRequested": true,
            "inPersonVerified": true,
          },
        ),
        "referrer",
      );
      expect(
        PartyListScreen.inPersonPartyReferrerUid(
          documentPath: "users/plain_referrer/referrals/me",
          myUid: "me",
          data: const <String, dynamic>{},
        ),
        isNull,
      );
      expect(
        PartyListScreen.inPersonPartyReferrerUid(
          documentPath: "users/me/referrals/me",
          myUid: "me",
          data: const <String, dynamic>{
            "uid": "me",
            "partyInPersonQrRequested": true,
            "inPersonVerified": true,
          },
        ),
        isNull,
      );
    });

    test(
      "both badges reject requested-only, foreign, or mismatched referral rows",
      () {
        const verified = <String, dynamic>{
          "uid": "me",
          "partyInPersonQrRequested": true,
          "inPersonVerified": true,
        };
        for (final data in <Map<String, dynamic>>[
          {...verified, "inPersonVerified": false},
          {...verified, "partyInPersonQrRequested": false},
          {...verified, "uid": "someone_else"},
        ]) {
          expect(
            PartyListScreen.inPersonPartyReferrerUid(
              documentPath: "users/referrer/referrals/me",
              data: data,
              myUid: "me",
            ),
            isNull,
          );
        }
        for (final path in <String>[
          "referrals/me",
          "foreign/referrer/referrals/me",
          "users/referrer/business/custom/referrals/me",
          "users/referrer/referrals/other",
        ]) {
          expect(
            PartyListScreen.inPersonPartyReferrerUid(
              documentPath: path,
              data: verified,
              myUid: "me",
            ),
            isNull,
          );
        }
        expect(
          PartyListScreen.inPersonPartyReferralUid(
            documentPath: "users/me/referrals/peer",
            myUid: "me",
            data: const {"uid": "peer", "partyInPersonQrRequested": true},
          ),
          isNull,
        );
        expect(
          PartyListScreen.inPersonPartyReferralUid(
            documentPath: "users/other/referrals/peer",
            myUid: "me",
            data: const {
              "uid": "peer",
              "partyInPersonQrRequested": true,
              "inPersonVerified": true,
            },
          ),
          isNull,
        );
      },
    );

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
      final party = File(
        "lib/screens/party/party_list_screen.dart",
      ).readAsStringSync();
      final meetups = File(
        "lib/services/meetup_service.dart",
      ).readAsStringSync();

      expect(party, contains("watchOnlinePartyUids"));
      expect(party, contains('value: "message"'));
      expect(party, contains("enabled: online"));
      expect(party, contains("Hot now"));
      expect(party, contains("New requests"));
      expect(meetups, contains("recipient_offline"));
    });
  });
}
