import "package:flutter/material.dart";
import "package:prox/services/meetup_flow_bootstrap.dart";

/// DevPostMeetupSim
/// A small dev-only widget to simulate the post-meetup flow.
class DevPostMeetupSim extends StatelessWidget {
  const DevPostMeetupSim({
    super.key,
    required this.chatId,
    required this.otherUid,
  });

  final String chatId;
  final String otherUid;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.play_arrow),
      label: const Text("Simulate Post-Meetup Flow"),
      onPressed: () async {
        await MeetupFlowBootstrap.instance.maybeRun(
          context: context,
          key: chatId,
          chatId: chatId,
          otherUid: otherUid,
          bothArrived: true,
        );
      },
    );
  }
}
