import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:firebase_storage/firebase_storage.dart";
import "package:flutter/material.dart";
import "package:image_picker/image_picker.dart";

import "package:prox/services/chat/chat_gate_service.dart";
import "package:prox/services/chat/chat_message_service.dart";
import "package:prox/services/meetup_service.dart";
import "package:prox/services/user_notes_service.dart";
import "package:prox/services/user_profile_service.dart";
import "package:prox/widgets/meetup_request_bar.dart";

class ChatThreadScreen extends StatefulWidget {
  final String chatId;
  final String otherUid;

  const ChatThreadScreen({
    super.key,
    required this.chatId,
    required this.otherUid,
  });

  static ChatThreadScreen fromArgs(Object? args) {
    final m = (args is Map) ? args : <String, dynamic>{};
    return ChatThreadScreen(
      chatId: (m["chatId"] ?? "").toString(),
      otherUid: (m["otherUid"] ?? "").toString(),
    );
  }

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> with WidgetsBindingObserver {
  final _text = TextEditingController();
  bool _sending = false;
  bool _sendingMedia = false;
  Timer? _readDebounce;
  Timer? _uiTick;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? "";

  CollectionReference<Map<String, dynamic>> get _msgRef => FirebaseFirestore.instance
      .collection("chats")
      .doc(widget.chatId)
      .collection("messages");

  DocumentReference<Map<String, dynamic>> get _chatRef =>
      FirebaseFirestore.instance.collection("chats").doc(widget.chatId);

  DocumentReference<Map<String, dynamic>> _partyDoc(String myUid) {
    return FirebaseFirestore.instance
        .collection("users")
        .doc(myUid)
        .collection("party")
        .doc(widget.otherUid);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _markReadNow();

    _uiTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _readDebounce?.cancel();
    _uiTick?.cancel();
    _text.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _markReadNow();
    }
  }

  void _markReadNow() {
    final myUid = _myUid;
    if (myUid.isEmpty) return;
    ChatMessageService.instance.markThreadRead(
      chatId: widget.chatId,
      myUid: myUid,
    );
  }

  void _scheduleReadClear() {
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 650), _markReadNow);
  }

  Future<void> _send({required bool canSend}) async {
    if (!canSend) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Chat is locked right now.")),
      );
      return;
    }

    final myUid = _myUid;
    if (myUid.isEmpty) return;

    final text = _text.text.trim();
    if (text.isEmpty) return;

    if (_sending) return;
    setState(() => _sending = true);

    try {
      await ChatMessageService.instance.sendText(
        chatId: widget.chatId,
        fromUid: myUid,
        toUid: widget.otherUid,
        text: text,
      );
      _text.clear();
      _markReadNow();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Message failed to send.")),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendPhoto({required bool canSend}) async {
    if (!canSend) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Chat is locked right now.")),
      );
      return;
    }

    final myUid = _myUid;
    if (myUid.isEmpty) return;
    if (_sendingMedia) return;

    final picker = ImagePicker();
    XFile? xf;
    try {
      xf = await picker.pickImage(source: ImageSource.camera, maxWidth: 1280, imageQuality: 72);
    } catch (_) {
      xf = null;
    }
    if (xf == null) return;

    setState(() => _sendingMedia = true);

    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = "chatMedia/${widget.chatId}/$myUid-$ts.jpg";
      final ref = FirebaseStorage.instance.ref().child(path);

      final bytes = await xf.readAsBytes();
      await ref.putData(bytes, SettableMetadata(contentType: "image/jpeg")).timeout(const Duration(minutes: 2));

      final url = await ref.getDownloadURL();

      await _msgRef.add(<String, Object?>{
        "from": myUid,
        "to": widget.otherUid,
        "type": "image",
        "imageUrl": url,
        "text": "",
        "ts": FieldValue.serverTimestamp(),
        "read": false,
      });

      _markReadNow();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Photo sent.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Photo failed to send: $e")));
      }
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  Widget _chatGateBanner(ChatGateStatus gate, {required bool isParty}) {
    if (isParty) return const SizedBox.shrink();

    final myUid = _myUid;
    final requestedByMe = gate.requestedBy.isNotEmpty && gate.requestedBy == myUid;

    if (gate.isAccepted) return const SizedBox.shrink();

    if (gate.isDeclined) {
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

    if (gate.isExpired) {
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
        child: const Text(
          "Respond from the Nearby user card. Accept opens chat right away.",
        ),
      ),
    );
  }

  String _fmtMMSS(Duration d) {
    final s = d.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, "0");
    final ss = (s % 60).toString().padLeft(2, "0");
    return "$mm:$ss";
  }

  Widget _meetupDeclineLockBanner(Duration left) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_clock, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Meetup was declined. Chat actions are paused for ${_fmtMMSS(left)}.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, "0");
    final ap = dt.hour >= 12 ? "PM" : "AM";
    return "$h:$m $ap";
  }

  String _fmtDateTime(DateTime dt) {
    final m = dt.month.toString().padLeft(2, "0");
    final d = dt.day.toString().padLeft(2, "0");
    final y = dt.year.toString();
    return "$m/$d/$y ${_fmtTime(dt)}";
  }

  String _fmtLatLng(dynamic latAny, dynamic lngAny) {
    final double? lat = (latAny is num) ? latAny.toDouble() : double.tryParse("$latAny");
    final double? lng = (lngAny is num) ? lngAny.toDouble() : double.tryParse("$lngAny");
    if (lat == null || lng == null) return "Location: (not set)";
    return "Location: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}";
  }

  Future<void> _editPrivateNote({required String initial}) async {
    final ctrl = TextEditingController(text: initial);
    final debouncer = NoteSaveDebouncer();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final bottom = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Private note",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                "Only you can see this.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 6,
                minLines: 3,
                decoration: const InputDecoration(
                  hintText: "Type a private note about this person...",
                ),
                onChanged: (_) {
                  debouncer.schedule(const Duration(milliseconds: 450), () {
                    UserNotesService.instance.setNote(
                      otherUid: widget.otherUid,
                      text: ctrl.text,
                    );
                  });
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        await UserNotesService.instance.setNote(
                          otherUid: widget.otherUid,
                          text: ctrl.text,
                        );
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      child: const Text("Save"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    debouncer.dispose();
    ctrl.dispose();
  }

  Widget _meetupRecapCard(Map<String, dynamic> recap, {required String notePreview}) {
    final cs = Theme.of(context).colorScheme;

    DateTime? completed;
    final cAny = recap["completedAt"];
    if (cAny is Timestamp) completed = cAny.toDate();

    final kwsAny = recap["matchedKeywords"];
    final List<String> kws = (kwsAny is List)
        ? kwsAny.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
        : const <String>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Meetup recap",
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                if (notePreview.trim().isNotEmpty)
                  Icon(Icons.note_alt_outlined, color: cs.onSurfaceVariant, size: 18),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              completed == null ? "Completed: (unknown time)" : "Completed: ${_fmtDateTime(completed)}",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              _fmtLatLng(recap["lat"], recap["lng"]),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            if (kws.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: kws.take(8).map((k) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: cs.outline.withValues(alpha: 0.24)),
                      color: cs.surface,
                    ),
                    child: Text(
                      k,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final current = await UserNotesService.instance.getNoteText(
                        otherUid: widget.otherUid,
                      );
                      if (!mounted) return;
                      await _editPrivateNote(initial: current);
                    },
                    icon: const Icon(Icons.edit_note),
                    label: Text(notePreview.trim().isEmpty ? "Add private note" : "Edit private note"),
                  ),
                ),
              ],
            ),
            if (notePreview.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                notePreview.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bubble({
    required bool mine,
    required String text,
    required DateTime? ts,
    required bool read,
    required String type,
    required String imageUrl,
  }) {
    final cs = Theme.of(context).colorScheme;
    final bg = mine ? cs.primary.withValues(alpha: 0.20) : cs.surfaceContainerHighest;
    final border = cs.outline.withValues(alpha: 0.25);

    Widget body;
    if (type == "image" && imageUrl.trim().isNotEmpty) {
      body = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          height: 220,
          width: 280,
          errorBuilder: (_, __, ___) =>
              const SizedBox(height: 80, child: Center(child: Text("Image failed"))),
          loadingBuilder: (context, child, p) {
            if (p == null) return child;
            return const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          },
        ),
      );
    } else {
      body = Text(text);
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            body,
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ts == null ? "" : _fmtTime(ts),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
                if (mine) ...[
                  const SizedBox(width: 8),
                  Icon(
                    read ? Icons.done_all : Icons.done,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _uidFallback(String uid) {
    final s = uid.trim();
    if (s.isEmpty) return "Chat";
    final n = s.length >= 6 ? 6 : s.length;
    return "User ${s.substring(0, n)}";
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _myUid;

    return StreamBuilder<UserProfile?>(
      stream: UserProfileService.instance.watchProfile(widget.otherUid),
      builder: (context, ps) {
        final name = (ps.data?.displayName ?? "").trim();
        final title = name.isNotEmpty ? name : _uidFallback(widget.otherUid);

        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _chatRef.snapshots(),
            builder: (context, chatSnap) {
              final chatData = chatSnap.data?.data();
              final gate = ChatGateStatus.fromChatDoc(chatData);

              final recapAny = (chatData ?? const <String, dynamic>{})["meetupRecap"];
              final Map<String, dynamic> recap =
                  (recapAny is Map) ? Map<String, dynamic>.from(recapAny) : <String, dynamic>{};

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: (myUid.isEmpty) ? const Stream.empty() : _partyDoc(myUid).snapshots(),
                builder: (context, partySnap) {
                  final isParty = partySnap.data?.exists == true;

                  return StreamBuilder<MeetupRequestState?>(
                    stream: MeetupService.instance.watchRequestState(chatId: widget.chatId),
                    builder: (context, meetupSnap) {
                      final meetupState = meetupSnap.data;
                      final Duration? declineLeft =
                          MeetupService.instance.declineCooldownLeftFromState(meetupState);
                      final bool declineCooling =
                          (declineLeft != null && declineLeft > Duration.zero);

                      final bool chatOpen = gate.isAccepted || isParty;
                      final bool canSend = chatOpen && !declineCooling;

                      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: UserNotesService.instance.watchNote(otherUid: widget.otherUid),
                        builder: (context, noteSnap) {
                          final nd = noteSnap.data?.data() ?? const <String, dynamic>{};
                          final noteText = (nd["text"] ?? "").toString();
                          final notePreview = noteText.trim();

                          return Column(
                            children: [
                              _chatGateBanner(gate, isParty: isParty),

                              if (recap.isNotEmpty)
                                _meetupRecapCard(recap, notePreview: notePreview),

                              if (declineCooling) _meetupDeclineLockBanner(declineLeft),

                              MeetupRequestBar(
                                chatId: widget.chatId,
                                otherUid: widget.otherUid,
                                isParty: isParty,
                                chatOpen: chatOpen,
                              ),

                              Expanded(
                                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                  stream: _msgRef.orderBy("ts", descending: true).limit(80).snapshots(),
                                  builder: (context, snap) {
                                    final docs = snap.data?.docs ?? const [];
                                    if (myUid.isNotEmpty && docs.isNotEmpty) _scheduleReadClear();
                                    if (docs.isEmpty) return const Center(child: Text("Say hi"));

                                    return ListView.builder(
                                      reverse: true,
                                      itemCount: docs.length,
                                      itemBuilder: (context, i) {
                                        final d = docs[i].data();
                                        final from = (d["from"] ?? "").toString();
                                        final text = (d["text"] ?? "").toString();
                                        final type = (d["type"] ?? "").toString();
                                        final imageUrl =
                                            (d["imageUrl"] ?? d["mediaUrl"] ?? "").toString();
                                        final mine = from == myUid;

                                        final tsAny = d["ts"];
                                        DateTime? ts;
                                        if (tsAny is Timestamp) ts = tsAny.toDate();

                                        final read = (d["read"] == true);

                                        return _bubble(
                                          mine: mine,
                                          text: text,
                                          ts: ts,
                                          read: read,
                                          type: type,
                                          imageUrl: imageUrl,
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),

                              SafeArea(
                                top: false,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                                  child: Row(
                                    children: [
                                      IconButton(
                                        tooltip: "Camera",
                                        onPressed: (!canSend || _sendingMedia)
                                            ? null
                                            : () => _pickAndSendPhoto(canSend: canSend),
                                        icon: _sendingMedia
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Icon(Icons.camera_alt_outlined),
                                      ),
                                      Expanded(
                                        child: TextField(
                                          controller: _text,
                                          enabled: canSend,
                                          textInputAction: TextInputAction.send,
                                          onSubmitted: (_) => _send(canSend: canSend),
                                          decoration: InputDecoration(
                                            hintText: canSend
                                                ? "Message..."
                                                : (declineCooling
                                                    ? "Paused after meetup decline..."
                                                    : "Chat locked until accepted..."),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      FilledButton(
                                        onPressed: _sending ? null : () => _send(canSend: canSend),
                                        child: _sending
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Icon(Icons.send),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
