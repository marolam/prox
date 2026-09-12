import 'package:flutter/material.dart';
import 'package:prox/services/party_connection_service.dart';
import 'package:prox/widgets/meetup_rating_form.dart';
import 'package:prox/services/simple_mode/simple_mode_policy.dart';
import 'package:prox/services/user_settings_service.dart';

class RatingScreen extends StatelessWidget {
  const RatingScreen({super.key, required this.chatId, required this.otherUid});
  final String chatId;
  final String otherUid;
  static RatingScreen fromArgs(Object? args) {
    final m = args is Map ? args : <String, dynamic>{};
    return RatingScreen(
      chatId: (m['chatId'] ?? '').toString(),
      otherUid: (m['otherUid'] ?? '').toString(),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Rate Meetup')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            MeetupRatingForm(
              partyRequiresNormalMode: SimpleModePolicy.isActive,
              save: (thumb, choice, comment) async {
                final result = await PartyConnectionService.instance.act(
                  otherUid,
                  'feedback',
                  chatId: chatId,
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
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/home', (route) => false),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    ),
  );
}
