import 'package:flutter/material.dart';
import 'package:prox/services/party_connection_service.dart';
import 'package:prox/widgets/meetup_rating_form.dart';
import 'package:prox/services/simple_mode/simple_mode_policy.dart';
import 'package:prox/services/user_settings_service.dart';

class RatingSheet extends StatelessWidget {
  const RatingSheet({
    super.key,
    required this.chatId,
    required this.peerUid,
    this.meetupId,
  });
  final String chatId;
  final String peerUid;
  final String? meetupId;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: MeetupRatingForm(
        partyRequiresNormalMode: SimpleModePolicy.isActive,
        save: (thumb, choice, comment) async {
          final result = await PartyConnectionService.instance.act(
            peerUid,
            'feedback',
            chatId: meetupId ?? chatId,
            thumb: thumb,
            partyDecision: choice,
            comment: comment,
          );
          if (choice == 'add' && SimpleModePolicy.isActive) {
            UserSettingsService.instance.unlockPartyFromSimpleMode();
          }
          return result;
        },
      ),
    ),
  );
}
