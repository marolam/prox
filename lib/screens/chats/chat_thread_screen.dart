import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/services/action_receipt_service.dart";
import "package:prox/services/chat_media_service.dart";
import "package:prox/services/chat_service.dart";
import "package:prox/services/first_user_journey/first_user_journey_service.dart";
import "package:prox/services/meetup_service.dart";
import "package:prox/services/metrics/metrics_event_service.dart";
import "package:prox/services/privacy/block_service.dart";
import "package:prox/services/reciprocity/reciprocity_service.dart";
import "package:prox/services/user_settings_service.dart";
import "package:prox/widgets/chat/chat_input_bar.dart";
import "package:prox/widgets/tutorial/tutorial_overlay.dart";
import "package:prox/widgets/tutorial/tutorial_target.dart";

/// Local helper to intentionally ignore a Future without analyzer noise.
void _unawaited(Future<void> f) {
  // ignore: discarded_futures
  f;
}

class ChatThreadScreen extends StatefulWidget {
  final String chatId;
  final String otherUid;
  final String? otherName;

  const ChatThreadScreen({
    super.key,
    required this.chatId,
    required this.otherUid,
    this.otherName,
  });

  static ChatThreadScreen fromArgs(Object? args) {
    final m = (args is Map) ? args : <String, dynamic>{};
    final chatId = (m["chatId"] ?? "").toString();
    final otherUid = (m["otherUid"] ?? "").toString();
    final otherName = (m["otherName"] as String?)?.toString();
    return ChatThreadScreen(
      chatId: chatId,
      otherUid: otherUid,
      otherName: otherName,
    );
  }

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _scroll = ScrollController();

  final Set<String> _seenIncomingMessageIds = <String>{};

  bool _journeyChatMarked = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _isBusinessMode() {
    return UserSettingsService.instance.current.uxMode == AppUxMode.business;
  }

  void _receiptBestEffort({
    required String kind,
    required String title,
    required String detail,
  }) {
    if (!_isBusinessMode()) return;
    _unawaited(
      ActionReceiptService.instance.add(
        kind: kind,
        title: title,
        detail: detail,
      ),
    );
  }

  void _markFirstChatIfNeeded() {
    if (_journeyChatMarked) return;
    _journeyChatMarked = true;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return;
    FirstUserJourneyService.instance.markFirstChatSent(uid);
  }

  Future<void> _pickMedia() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text("Take photo"),
              onTap: () => Navigator.pop(ctx, "camera"),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text("Choose from gallery"),
              onTap: () => Navigator.pop(ctx, "gallery"),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    final media = ChatMediaService.instance;
    final x = choice == "camera"
        ? await media.takePhoto()
        : await media.pickFromGallery();
    if (x == null) return;

    final url = await media.uploadChatImage(chatId: widget.chatId, file: x);
    await ChatService.instance.sendImageMessage(
      chatId: widget.chatId,
      imageUrl: url,
      caption: "",
      otherUid: widget.otherUid,
    );

    await MetricsEventService.instance.log("chat_send_image", meta: {
      "chatId": widget.chatId,
      "otherUid": widget.otherUid,
    });

    _markFirstChatIfNeeded();
  }

  Future<void> _sendText(String text) async {
    await ChatService.instance.sendMessage(
      chatId: widget.chatId,
      text: text,
      otherUid: widget.otherUid,
    );

    await MetricsEventService.instance.log("chat_send_text", meta: {
      "chatId": widget.chatId,
      "otherUid": widget.otherUid,
      "len": text.trim().length,
    });

    _markFirstChatIfNeeded();

    if (!_scroll.hasClients) return;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _trackIncomingBestEffort(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    for (final doc in docs) {
      final data = doc.data();
      final from = (data["from"] ?? "").toString().trim();
      if (from.isEmpty) continue;
      if (from == me.uid) continue;

      if (_seenIncomingMessageIds.contains(doc.id)) continue;
      _seenIncomingMessageIds.add(doc.id);

      if (from == widget.otherUid) {
        ReciprocityService.instance.recordIncomingMessage(widget.otherUid);
      }
    }

    if (_seenIncomingMessageIds.length > 1200) {
      _seenIncomingMessageIds.clear();
    }
  }

  Future<void> _requestMeetup() async {
    final me = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (me.trim().isEmpty) return;

    await BlockService.instance.ensureLoaded();
    if (BlockService.instance.isBlockedSync(widget.otherUid)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You blocked this user. Unblock them to request meetups."),
        ),
      );
      return;
    }

    try {
      await MeetupService.instance.requestMeetup(
        chatId: widget.chatId,
        otherUid: widget.otherUid,
      );

      _receiptBestEffort(
        kind: "meetup",
        title: "Meetup requested",
        detail: "chatId=${widget.chatId}; otherUid=${widget.otherUid}",
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Meetup request sent.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$e")),
      );
    }
  }

  Future<void> _acceptMeetup() async {
    try {
      await MeetupService.instance.acceptMeetupRequest(
        chatId: widget.chatId,
        otherUid: widget.otherUid,
      );

      if (!mounted) return;
      Navigator.of(context).pushNamed(
        "/meetup_plan",
        arguments: {"chatId": widget.chatId, "otherUid": widget.otherUid},
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
    }
  }

  Future<void> _declineMeetup() async {
    try {
      await MeetupService.instance.declineMeetupRequest(
        chatId: widget.chatId,
        otherUid: widget.otherUid,
      );

      if (!mounted) return;
      final shouldBlock = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: const [
                    Icon(Icons.shield_outlined),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Block meetup requests from this user?",
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "If you block them, they won't be able to request meetups from you again (on this device). "
                    "You can undo this in Settings  Blocked users.",
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text("No thanks"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text("Block"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      if (shouldBlock == true) {
        await BlockService.instance.block(widget.otherUid);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("User blocked.")),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Meetup request declined.")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
    }
  }

  Widget _meetupBanner(MeetupRequestState? state) {
    final cs = Theme.of(context).colorScheme;
    final me = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (me.trim().isEmpty) return const SizedBox.shrink();

    final status = state?.status ?? "";
    if (status.isEmpty) return const SizedBox.shrink();

    // Hide noisy states
    if (status == "completed") return const SizedBox.shrink();

    String title = "Meetup";
    String subtitle = "";
    List<Widget> actions = const [];

    if (status == "requested") {
      final requestedBy = (state?.requestedBy ?? "").trim();
      final expiresAt = state?.expiresAt?.toDate();
      final remaining = expiresAt?.difference(DateTime.now());

      // If I'm blocked locally, auto-decline inbound requests (local-only enforcement).
      _unawaited(BlockService.instance.ensureLoaded());
      if (requestedBy.isNotEmpty &&
          requestedBy != me &&
          BlockService.instance.isBlockedSync(widget.otherUid)) {
        _unawaited(
          MeetupService.instance.declineMeetupRequest(
            chatId: widget.chatId,
            otherUid: widget.otherUid,
          ),
        );
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Meetup blocked",
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                "You blocked this user on this device. Their meetup request was declined.",
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        );
      }

      // If expired, flip doc best-effort so both devices converge.
      if (remaining != null && remaining.isNegative) {
        _unawaited(
          MeetupService.instance.expireRequestBestEffort(chatId: widget.chatId),
        );
      }

      title = requestedBy == me ? "Meetup requested" : "Meetup request";
      subtitle = requestedBy == me
          ? "Waiting for them to accept."
          : "They want to meet up. Accept or decline.";

      final countdown = (remaining == null)
          ? ""
          : (remaining.isNegative
              ? "Expired"
              : "Expires in ${remaining.inMinutes}m");
      if (countdown.isNotEmpty) {
        subtitle = "$subtitle  $countdown";
      }

      if (requestedBy != me) {
        actions = [
          Expanded(
            child: TextButton.icon(
              onPressed: _declineMeetup,
              icon: const Icon(Icons.close),
              label: const Text("Decline"),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: _acceptMeetup,
              icon: const Icon(Icons.check),
              label: const Text("Accept"),
            ),
          ),
        ];
      } else {
        actions = [
          Expanded(
            child: FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.hourglass_top),
              label: const Text("Pending"),
            ),
          ),
        ];
      }
    } else if (status == "accepted") {
      title = "Meetup accepted";
      subtitle = "Pick the meetup spot now.";

      actions = [
        Expanded(
          child: FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pushNamed(
                "/meetup_plan",
                arguments: {"chatId": widget.chatId, "otherUid": widget.otherUid},
              );
            },
            icon: const Icon(Icons.location_on),
            label: const Text("Plan location"),
          ),
        ),
      ];
    } else if (status == "declined") {
      title = "Meetup declined";
      subtitle = "You can request again later.";
      actions = [
        Expanded(
          child: TextButton(
            onPressed: _requestMeetup,
            child: const Text("Request again"),
          ),
        ),
      ];
    } else if (status == "expired") {
      title = "Meetup request expired";
      subtitle = "Request again when you're both ready.";
      actions = [
        Expanded(
          child: TextButton(
            onPressed: _requestMeetup,
            child: const Text("Request again"),
          ),
        ),
      ];
    } else if (status == "live") {
      title = "Meetup live";
      subtitle = "Open the live meetup screen.";
      actions = [
        Expanded(
          child: FilledButton(
            onPressed: () {
              Navigator.of(context).pushNamed(
                "/meetup_live",
                arguments: {
                  "meetupId": widget.chatId,
                  "chatId": widget.chatId,
                  "otherUid": widget.otherUid,
                },
              );
            },
            child: const Text("Open meetup"),
          ),
        ),
      ];
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Row(children: actions),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stream = ChatService.instance.messagesStream(widget.chatId);
    final title = (widget.otherName?.trim().isNotEmpty ?? false)
        ? widget.otherName!.trim()
        : "Chat";

    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TutorialTarget(
            id: "chat.request_meetup",
            message:
                "Request meetup\n\nUse the big button to request a meetup. Your match can accept or decline with a short countdown, and you can block future meetup requests if needed.",
            child: IconButton(
              icon: const Icon(Icons.handshake_outlined),
              tooltip: "Request meetup",
              onPressed: _requestMeetup,
            ),
          ),
          TutorialTarget(
            id: "chat.plan_meetup",
            message:
                "Plan meetup\n\nPick a meetup location and time with your match. During a meetup, Prox can help both sides coordinate and confirm arrival.",
            child: IconButton(
              icon: const Icon(Icons.location_on),
              tooltip: "Plan meetup",
              onPressed: () {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if ((uid?.trim().isNotEmpty ?? false)) {
                  FirstUserJourneyService.instance.markMeetupPlanned(uid!);
                }

                _receiptBestEffort(
                  kind: "meetup",
                  title: "Meetup planner opened",
                  detail: "chatId=${widget.chatId}; otherUid=${widget.otherUid}",
                );

                Navigator.of(context).pushNamed(
                  "/meetup_plan",
                  arguments: {"chatId": widget.chatId, "otherUid": widget.otherUid},
                );
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.handshake_outlined),
                label: const Text("Request meetup"),
                onPressed: _requestMeetup,
              ),
            ),
          ),
          StreamBuilder<MeetupRequestState?>(
            stream: MeetupService.instance.watchRequestState(chatId: widget.chatId),
            builder: (context, snap) => _meetupBanner(snap.data),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                final docs = snap.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                if (docs.isNotEmpty) {
                  _trackIncomingBestEffort(docs);
                }

                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i].data();
                    final text = (d["text"] ?? "").toString();
                    final img = (d["imageUrl"] as String?)?.toString();
                    if (img != null && img.isNotEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(img),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Text(text),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          ChatInputBar(
            onSend: _sendText,
            onPickMedia: _pickMedia,
          ),
        ],
      ),
    );

    return TutorialOverlayHost(
      logoTopPadding: 8,
      logoLeftPadding: 12,
      child: scaffold,
    );
  }
}