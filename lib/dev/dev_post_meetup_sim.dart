import 'package:flutter/material.dart';
import 'package:prox/screens/referral/referral_demo_walkthrough_screen.dart';

/// Isolated walkthrough: never marks arrival, awards points, or rates a real meetup.
class DevPostMeetupSim extends StatelessWidget {
  const DevPostMeetupSim({
    super.key,
    required this.chatId,
    required this.otherUid,
  });
  final String chatId;
  final String otherUid;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    icon: const Icon(Icons.play_arrow),
    label: const Text('Explore the meetup example'),
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ReferralDemoWalkthroughScreen(),
      ),
    ),
  );
}
