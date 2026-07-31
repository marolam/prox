import "package:flutter/material.dart";

class ChatGateBanner extends StatelessWidget {
  final bool isParty;
  final String myUid;
  final String status;
  final String requestedBy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const ChatGateBanner({
    super.key,
    required this.isParty,
    required this.myUid,
    required this.status,
    required this.requestedBy,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    if (isParty) return const SizedBox.shrink();

    final String effectiveStatus = status.trim();
    final bool isRequested = effectiveStatus == "requested";
    final bool isAccepted = effectiveStatus == "accepted";
    final bool isDeclined = effectiveStatus == "declined";
    final bool isExpired = effectiveStatus == "expired";
    final bool requestedByMe =
        isRequested && requestedBy.isNotEmpty && requestedBy == myUid;

    if (isAccepted || effectiveStatus.isEmpty) return const SizedBox.shrink();

    if (isDeclined) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
            ),
          ),
          child: const Text("Chat was declined."),
        ),
      );
    }

    if (isExpired) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
            ),
          ),
          child: const Text("Chat request expired. Send a new request from Nearby."),
        ),
      );
    }

    if (!isRequested) return const SizedBox.shrink();

    if (requestedByMe) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
            ),
          ),
          child: const Text("Chat request sent. Waiting for them to accept..."),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                "Chat request pending. Accept to start chatting now.",
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onAccept,
              child: const Text("Accept"),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onDecline,
              child: const Text("Decline"),
            ),
          ],
        ),
      ),
    );
  }
}