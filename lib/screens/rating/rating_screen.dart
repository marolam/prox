import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "package:prox/services/meetup_service.dart";
import "package:prox/services/metrics/metrics_event_service.dart";
import "package:prox/services/referral/referral_verification_service.dart";
import "package:prox/services/prox_points/prox_points_events_service.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/trust/trust_service.dart";
import "package:prox/services/simple_mode/simple_mode_policy.dart";
import "package:prox/services/user_settings_service.dart";

class RatingScreen extends StatefulWidget {
  final String chatId;
  final String otherUid;

  const RatingScreen({super.key, required this.chatId, required this.otherUid});

  static RatingScreen fromArgs(Object? args) {
    final m = (args is Map) ? args : <String, dynamic>{};
    final chatId = (m["chatId"] ?? "").toString();
    final otherUid = (m["otherUid"] ?? "").toString();
    return RatingScreen(chatId: chatId, otherUid: otherUid);
  }

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  bool _busy = false;
  bool _addToParty = true;

  Future<bool> _offerPartyUnlock() async {
    final switchAndAdd = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.groups_outlined),
        title: const Text("Keep this connection in Party"),
        content: const Text(
          "You completed the core meetup flow. To add this person to your Party and communicate after the meetup, switch to Normal Mode. The Party icon will be highlighted for you.",
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Not now"),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text("Switch and add"),
          ),
        ],
      ),
    );
    return switchAndAdd == true;
  }

  Future<void> _rate(bool up) async {
    if (_busy) return;

    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final wasSimpleMode = SimpleModePolicy.isActive;

    setState(() => _busy = true);

    try {
      await MeetupService.instance.submitThumb(
        chatId: widget.chatId,
        raterUid: me.uid,
        ratedUid: widget.otherUid,
        thumb: up,
        reason: null,
      );

      // Suggestion #1: quiet post-meet receipt
      // For now: thumbs-up => "would meet again = yes", thumbs-down => "not now".
      await TrustService.instance.recordWouldMeetAgain(
        yes: up,
        meetupId: widget.chatId,
        otherUid: widget.otherUid,
      );

      await MetricsEventService.instance.log(
        "rating_submitted",
        meta: {
          "chatId": widget.chatId,
          "otherUid": widget.otherUid,
          "thumb": up ? "up" : "down",
          "addToParty": _addToParty,
        },
      );

      // Local points feed (visibility + future awarding)
      await ProxPointsEventsService.instance.log(
        kind: "meetup_rated",
        title: up ? "Meetup rated (thumbs up)" : "Meetup rated (thumbs down)",
        delta: 0,
        meta: "chatId=${widget.chatId};other=${widget.otherUid}",
      );

      await ReferralVerificationService.instance.verifyInviteeIfEligible(
        inviteeUid: me.uid,
        chatId: widget.chatId,
        otherUid: widget.otherUid,
      );

      await MetricsEventService.instance.log(
        "referral_verify_attempted",
        meta: {"chatId": widget.chatId, "otherUid": widget.otherUid},
      );

      var shouldAddToParty = up && _addToParty && !wasSimpleMode;
      if (up && wasSimpleMode && mounted) {
        shouldAddToParty = await _offerPartyUnlock();
        if (shouldAddToParty) {
          UserSettingsService.instance.unlockPartyFromSimpleMode();
        }
      }
      if (shouldAddToParty) {
        await MeetupService.instance.addToParty(
          meUid: me.uid,
          friendUid: widget.otherUid,
          source: "postMeetup",
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted) return;
    ContextHelpService.instance.setContext("home:nearby");
    Navigator.of(context).pushNamedAndRemoveUntil("/home", (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text("Rate Meetup")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Card(
            elevation: 0,
            color: cs.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "How was it?",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (SimpleModePolicy.isActive)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.lock_outline),
                      title: const Text("Party unlocks in Normal Mode"),
                      subtitle: const Text(
                        "After a successful rating, you can switch modes and add this person to your Party.",
                      ),
                    )
                  else
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Add to your Party?"),
                      subtitle: const Text(
                        "If you thumbs-up, this will add them to Party immediately.",
                      ),
                      value: _addToParty,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _addToParty = v),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: "Thumbs up",
                        icon: const Icon(Icons.thumb_up, size: 46),
                        onPressed: _busy ? null : () => _rate(true),
                      ),
                      const SizedBox(width: 46),
                      IconButton(
                        tooltip: "Thumbs down",
                        icon: const Icon(Icons.thumb_down, size: 46),
                        onPressed: _busy ? null : () => _rate(false),
                      ),
                    ],
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
