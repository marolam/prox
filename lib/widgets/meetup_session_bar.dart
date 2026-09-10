import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter/material.dart";

import "package:prox/services/meetup_service.dart";
import "package:prox/services/party_service.dart";

class MeetupSessionBar extends StatelessWidget {
  const MeetupSessionBar({
    super.key,
    required this.meetupId,
    required this.otherUid,
    required this.currentScreen,
    required this.helpTitle,
    required this.helpMessage,
  });

  final String meetupId;
  final String otherUid;
  final String currentScreen;
  final String helpTitle;
  final String helpMessage;

  Future<void> _open(BuildContext context, String screen) async {
    if (screen == currentScreen) return;
    await MeetupService.instance.recordSessionScreen(
      meetupId: meetupId,
      screen: screen,
    );
    if (!context.mounted) return;
    final route = switch (screen) {
      "chat" => "/chat",
      "live" => "/meetup_live",
      _ => "/meetup_plan",
    };
    Navigator.of(context).pushReplacementNamed(
      route,
      arguments: <String, String>{"chatId": meetupId, "otherUid": otherUid},
    );
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(helpTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(helpMessage),
          ],
        ),
      ),
    );
  }

  Future<void> _showProfile(BuildContext context) async {
    final uid = otherUid.trim();
    if (uid.isEmpty) return;
    final isPartyMember = await PartyService.instance.isInMyParty(uid);
    final meetupSnap = await MeetupService.instance.meetupRef(meetupId).get();
    final meetup = meetupSnap.data() ?? <String, dynamic>{};
    final status = (meetup["status"] ?? "").toString().trim().toLowerCase();
    final isActiveMeetup =
        meetupSnap.exists &&
        status != "completed" &&
        status != "cancelled" &&
        status != "canceled" &&
        status != "expired";
    if (!isPartyMember && !isActiveMeetup) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.lock_outline),
          title: const Text("Profile no longer available"),
          content: const Text(
            "Profiles remain available after a meetup only when that person is in your Party.",
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Close"),
            ),
          ],
        ),
      );
      return;
    }
    final snap = await FirebaseFirestore.instance
        .collection("publicProfiles")
        .doc(uid)
        .get();
    if (!context.mounted) return;
    final data = snap.data() ?? <String, dynamic>{};
    final alias = (data["alias"] ?? data["displayName"] ?? "Match").toString();
    final bio = (data["bio"] ?? data["about"] ?? "No profile summary yet.")
        .toString();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(alias, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(bio),
            const SizedBox(height: 12),
            Text(
              "User ID: $uid",
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            _item(context, "chat", Icons.chat_bubble_outline, "Chat"),
            _item(context, "planner", Icons.edit_location_alt_outlined, "Plan"),
            _item(context, "live", Icons.map_outlined, "Live"),
            IconButton(
              tooltip: "View participant profile",
              onPressed: () => _showProfile(context),
              icon: const Icon(Icons.person_outline),
            ),
            IconButton(
              tooltip: "What do I do?",
              onPressed: () => _showHelp(context),
              icon: const Icon(Icons.help_outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    String screen,
    IconData icon,
    String label,
  ) {
    return IconButton(
      tooltip: label,
      onPressed: screen == currentScreen ? null : () => _open(context, screen),
      icon: Icon(icon),
      isSelected: screen == currentScreen,
    );
  }
}
