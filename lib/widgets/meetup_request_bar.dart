import "dart:async";

import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "package:prox/services/meetup_service.dart";
import "package:prox/utils/safe_ui.dart";

class MeetupRequestBar extends StatefulWidget {
  final String chatId;
  final String otherUid;
  final bool isParty;

  /// When false (and not Party), meetup actions are disabled and we show a lock banner.
  final bool chatOpen;

  const MeetupRequestBar({
    super.key,
    required this.chatId,
    required this.otherUid,
    required this.isParty,
    required this.chatOpen,
  });

  @override
  State<MeetupRequestBar> createState() => _MeetupRequestBarState();
}

class _MeetupRequestBarState extends State<MeetupRequestBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, "0");
    final ss = (s % 60).toString().padLeft(2, "0");
    return "$mm:$ss";
  }

  DateTime? _deadlineFromRequest(MeetupRequestState s) {
    if (s.expiresAt != null) return s.expiresAt!.toDate();
    if (s.requestedAt != null) {
      return s.requestedAt!.toDate().add(MeetupService.requestWindow);
    }
    return null;
  }

  DateTime? _cooldownUntil(MeetupRequestState s) {
    if (s.declinedAt == null) return null;
    return s.declinedAt!.toDate().add(MeetupService.declineCooldown);
  }

  Widget _lockedBanner(BuildContext context, {required String text}) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    // Party: fast path-no request/accept needed. Show quick plan button.
    if (widget.isParty) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Icon(Icons.group, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Party member: quick actions enabled",
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            FilledButton.icon(
              onPressed: uid.isEmpty
                  ? null
                  : () {
                      Navigator.of(context).pushNamed(
                        "/meetup_plan",
                        arguments: {"chatId": widget.chatId, "otherUid": widget.otherUid},
                      );
                    },
              icon: const Icon(Icons.handshake_outlined),
              label: const Text("Meet up"),
            ),
          ],
        ),
      );
    }

    // Non-party: require chat to be accepted/open before any meetup workflow.
    if (!widget.chatOpen) {
      return _lockedBanner(context, text: "Accept chat to request a meetup.");
    }

    return StreamBuilder<MeetupRequestState?>(
      stream: MeetupService.instance.watchRequestState(chatId: widget.chatId),
      builder: (context, snap) {
        final s = snap.data;

        // No active request: allow request
        if (s == null || s.status.isEmpty || s.status == "expired") {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: uid.isEmpty
                    ? null
                    : () async {
                        try {
                          await MeetupService.instance.requestMeetup(
                            chatId: widget.chatId,
                            otherUid: widget.otherUid,
                          );
                          safeSnack(context, "Meetup request sent");
                        } catch (_) {
                          safeSnack(context, "Could not send meetup request");
                        }
                      },
                icon: const Icon(Icons.handshake_outlined),
                label: const Text("Request meetup"),
              ),
            ),
          );
        }

        // Requested: show accept/decline for recipient, pending banner for requester + countdown
        if (s.status == "requested") {
          final requestedByMe = s.requestedBy.isNotEmpty && s.requestedBy == uid;

          final DateTime? deadline = _deadlineFromRequest(s);
          final Duration? left =
              deadline == null ? null : deadline.difference(DateTime.now());

          // Best-effort expire when we detect time passed.
          if (left != null && left <= Duration.zero) {
            // ignore: discarded_futures
            MeetupService.instance.expireRequestBestEffort(chatId: widget.chatId);
          }

          final String timerLabel = (left == null)
              ? ""
              : (left <= Duration.zero ? " (expired)" : "  ${_fmt(left)}");

          if (requestedByMe) {
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
              ),
              child: Row(
                children: [
                  Icon(Icons.hourglass_bottom, color: cs.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Meetup request sent$timerLabel. Waiting for them to accept...",
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (uid.isEmpty || (left != null && left <= Duration.zero))
                        ? null
                        : () async {
                            try {
                              await MeetupService.instance.acceptMeetupRequest(
                                chatId: widget.chatId,
                                otherUid: widget.otherUid,
                              );
                              safeSnack(context, "Meetup accepted");
                            } catch (_) {
                              safeSnack(context, "Could not accept meetup");
                            }
                          },
                    icon: const Icon(Icons.check),
                    label: Text(
                      left != null && left > Duration.zero ? "Accept (${_fmt(left)})" : "Accept",
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (uid.isEmpty || (left != null && left <= Duration.zero))
                        ? null
                        : () async {
                            try {
                              await MeetupService.instance.declineMeetupRequest(
                                chatId: widget.chatId,
                                otherUid: widget.otherUid,
                              );
                              safeSnack(context, "Meetup declined");
                            } catch (_) {
                              safeSnack(context, "Could not decline meetup");
                            }
                          },
                    icon: const Icon(Icons.close),
                    label: const Text("Decline"),
                  ),
                ),
              ],
            ),
          );
        }

        // Accepted: allow planner screen
        if (s.status == "accepted") {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: uid.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).pushNamed(
                          "/meetup_plan",
                          arguments: {"chatId": widget.chatId, "otherUid": widget.otherUid},
                        );
                      },
                icon: const Icon(Icons.location_on_outlined),
                label: const Text("Plan meetup location"),
              ),
            ),
          );
        }

        // Declined: block re-request until cooldown passes (block-on-decline)
        if (s.status == "declined") {
          final DateTime? until = _cooldownUntil(s);
          final Duration? left = until == null ? null : until.difference(DateTime.now());
          final bool cooling = left != null && left > Duration.zero;
          final Duration leftSafe = left ?? Duration.zero;

          return Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Icon(Icons.block_flipped, color: cs.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    cooling
                        ? "Meetup was declined. You can request again in ${_fmt(leftSafe)}."
                        : "Meetup was declined.",
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: (uid.isEmpty || cooling)
                      ? null
                      : () async {
                          try {
                            await MeetupService.instance.requestMeetup(
                              chatId: widget.chatId,
                              otherUid: widget.otherUid,
                            );
                            safeSnack(context, "Meetup request sent");
                          } catch (_) {
                            safeSnack(context, "Could not send meetup request");
                          }
                        },
                  child: Text(cooling ? "Wait" : "Request again"),
                ),
              ],
            ),
          );
        }

        // Live/completed/etc: no CTA here (meetup UI handles)
        return const SizedBox.shrink();
      },
    );
  }
}
