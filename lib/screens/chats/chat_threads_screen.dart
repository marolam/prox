import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/chat_service.dart";
import "package:prox/services/party_service.dart";
import "dart:async";

import "chat_thread_screen.dart";

/// Lists /chats where current uid is a participant.
/// NOTE: orderBy(lastTs) removed temporarily to avoid composite index crash on web.
/// Re-enable after index is deployed.
class ChatThreadsScreen extends StatefulWidget {
  const ChatThreadsScreen({super.key});

  @override
  State<ChatThreadsScreen> createState() => _ChatThreadsScreenState();
}

class _ChatThreadsScreenState extends State<ChatThreadsScreen> {
  static const Duration _firstLoadTimeout = Duration(seconds: 12);
  static const Duration _staleChatAge = Duration(hours: 24);
  Timer? _timeoutTimer;
  bool _showLoadTimeout = false;
  int _reloadKey = 0;
  final Set<String> _cleanupInFlight = <String>{};
  int _selectedFilterIndex = 0;

  @override
  void initState() {
    super.initState();
    _startLoadTimeout();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _startLoadTimeout() {
    _timeoutTimer?.cancel();
    _showLoadTimeout = false;
    _timeoutTimer = Timer(_firstLoadTimeout, () {
      if (!mounted) return;
      setState(() => _showLoadTimeout = true);
    });
  }

  void _markLoaded() {
    if (_timeoutTimer != null) {
      _timeoutTimer?.cancel();
      _timeoutTimer = null;
    }
    if (_showLoadTimeout) {
      setState(() => _showLoadTimeout = false);
    }
  }

  void _retryLoad() {
    setState(() {
      _reloadKey++;
    });
    _startLoadTimeout();
  }

  Future<void> _pushWithHelpContext(
    BuildContext context, {
    required String contextKey,
    required Widget page,
  }) async {
    final previous = ContextHelpService.instance.contextKey.value;
    ContextHelpService.instance.setContext(contextKey);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    ContextHelpService.instance.setContext(previous);
  }

  String _deriveOtherUid(Map<String, dynamic> d, String me) {
    final p = d["participants"];
    if (p is List) {
      for (final x in p) {
        final s = (x ?? "").toString().trim();
        if (s.isNotEmpty && s != me) return s;
      }
    }
    return "";
  }

  List<String> _participants(Map<String, dynamic> d) {
    final p = d["participants"];
    if (p is! List) return const <String>[];
    final out = <String>[];
    final seen = <String>{};
    for (final x in p) {
      final s = (x ?? "").toString().trim();
      if (s.isEmpty || seen.contains(s)) continue;
      seen.add(s);
      out.add(s);
    }
    return out;
  }

  bool _isGroupChat(Map<String, dynamic> d) {
    final type = (d["type"] ?? "").toString().trim();
    final participants = _participants(d);
    if (participants.length > 2) return true;
    return type == "group" || type == "group_moderated";
  }

  bool _isUnread(Map<String, dynamic> d, String me) {
    final lastFrom = (d["lastFrom"] ?? "").toString().trim();
    if (lastFrom.isEmpty || lastFrom == me) return false;
    return true;
  }

  bool _isIncomingChatRequest(Map<String, dynamic> d, String me) {
    final gate = (d["chatGate"] is Map)
        ? Map<String, dynamic>.from(d["chatGate"] as Map)
        : const <String, dynamic>{};
    final status = (gate["status"] ?? "").toString().trim();
    final requestedBy = (gate["requestedBy"] ?? "").toString().trim();
    return status == "requested" && requestedBy.isNotEmpty && requestedBy != me;
  }

  String _chatTitle(Map<String, dynamic> d, String chatId, String me) {
    final explicit = (d["title"] ?? "").toString().trim();
    if (explicit.isNotEmpty) return explicit;

    if (_isGroupChat(d)) {
      final count = _participants(d).length;
      return count > 0 ? "Bridge Group ($count)" : "Bridge Group";
    }

    final otherUid = _deriveOtherUid(d, me);
    if (otherUid.isNotEmpty) return "Chat $otherUid";
    return "Chat $chatId";
  }

  String _chatSubtitle(Map<String, dynamic> d, String me, {required bool isParty}) {
    final pieces = <String>[];
    final isGroup = _isGroupChat(d);
    final incomingRequest = _isIncomingChatRequest(d, me);
    final unread = _isUnread(d, me);

    if (incomingRequest) pieces.add("ACTION NEEDED");
    if (unread) pieces.add("NEW");

    if (isGroup) {
      final owner = (d["ownerUid"] ?? d["moderatorUid"] ?? "").toString().trim();
      final count = _participants(d).length;
      pieces.add("$count members");
      if (owner.isNotEmpty) pieces.add("owner: $owner");
    } else if (isParty) {
      pieces.add("party-linked");
    }

    final last = (d["lastMessage"] ?? d["lastText"] ?? "").toString().trim();
    if (last.isNotEmpty) pieces.add(last);

    final ts = _readTs(d, const ["updatedAt", "lastTs", "createdAt"]);
    if (ts != null) pieces.add(ts.toLocal().toString());

    return pieces.join("  ·  ");
  }

  Future<void> _createBridgeGroupDialog() async {
    final titleCtrl = TextEditingController();
    final membersCtrl = TextEditingController();

    Future<void> submit(BuildContext modalContext) async {
      final raw = membersCtrl.text;
      final members = raw
          .split(RegExp(r"[\s,;]+"))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (members.length < 2) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Enter at least two member UIDs.")),
        );
        return;
      }

      try {
        final chatId = await ChatService.instance.createModeratedGroupChat(
          memberUids: members,
          title: titleCtrl.text,
        );

        if (!mounted) return;
        Navigator.of(modalContext).pop();

        final me = FirebaseAuth.instance.currentUser?.uid ?? "";
        final otherUid = members.firstWhere((u) => u != me, orElse: () => members.first);

        await _pushWithHelpContext(
          context,
          contextKey: "chats:thread",
          page: ChatThreadScreen(chatId: chatId, otherUid: otherUid, otherName: titleCtrl.text.trim().isEmpty ? null : titleCtrl.text.trim()),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not create bridge group: $e")),
        );
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (modalContext) {
        final bottom = MediaQuery.of(modalContext).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Create Bridge Group", style: Theme.of(modalContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text("You become moderator. Add at least two mutual party members to start."),
              const SizedBox(height: 12),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: "Group title (optional)"),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: membersCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: "Member UIDs",
                  hintText: "uid_a, uid_b, uid_c",
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => submit(modalContext),
                  icon: const Icon(Icons.groups_2_outlined),
                  label: const Text("Create moderated group"),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _manageGroupDialog({
    required String chatId,
    required String myUid,
    required List<String> participants,
  }) async {
    final addCtrl = TextEditingController();
    final removable = participants.where((u) => u != myUid).toList();
    final selectedToRemove = <String>{};

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> applyAdd() async {
              final ids = addCtrl.text
                  .split(RegExp(r"[\s,;]+"))
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              if (ids.isEmpty) return;
              try {
                await ChatService.instance.addMembersToModeratedGroupChat(
                  chatId: chatId,
                  memberUids: ids,
                );
                if (!mounted) return;
                addCtrl.clear();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Group members added.")),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Add failed: $e")),
                );
              }
            }

            Future<void> applyRemove() async {
              if (selectedToRemove.isEmpty) return;
              try {
                await ChatService.instance.removeMembersFromModeratedGroupChat(
                  chatId: chatId,
                  memberUids: selectedToRemove,
                );
                if (!mounted) return;
                Navigator.of(modalContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Selected members removed.")),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Remove failed: $e")),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Manage Group Members", style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: addCtrl,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: "Add member UIDs",
                      hintText: "uid_x uid_y",
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: applyAdd,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text("Add members"),
                    ),
                  ),
                  if (removable.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text("Remove members", style: Theme.of(ctx).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: removable.map((uid) {
                        final selected = selectedToRemove.contains(uid);
                        return FilterChip(
                          selected: selected,
                          label: Text(uid),
                          onSelected: (v) {
                            setModalState(() {
                              if (v) {
                                selectedToRemove.add(uid);
                              } else {
                                selectedToRemove.remove(uid);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: selectedToRemove.isEmpty ? null : applyRemove,
                        icon: const Icon(Icons.person_remove_alt_1),
                        label: const Text("Remove selected"),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  DateTime? _readTs(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final v = d[k];
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    }
    return null;
  }

  bool _isStale(Map<String, dynamic> d) {
    final now = DateTime.now();
    final ts = _readTs(d, const ["updatedAt", "lastTs", "createdAt"]);
    if (ts == null) return true;
    return now.difference(ts) > _staleChatAge;
  }

  Future<void> _cleanupIfNoActivity({
    required String chatId,
    required Map<String, dynamic> data,
  }) async {
    if (_cleanupInFlight.contains(chatId)) return;
    if (!_isStale(data)) return;

    _cleanupInFlight.add(chatId);
    try {
      final chatRef = FirebaseFirestore.instance.collection("chats").doc(chatId);
      final msgSnap = await chatRef.collection("messages").limit(1).get();
      if (msgSnap.docs.isNotEmpty) return;

      final meetupSnap = await FirebaseFirestore.instance
          .collection("meetups")
          .where("chatId", isEqualTo: chatId)
          .limit(1)
          .get();
      if (meetupSnap.docs.isNotEmpty) return;

      await chatRef.delete();
    } catch (_) {
      // Best-effort cleanup only.
    } finally {
      _cleanupInFlight.remove(chatId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.isEmpty) {
      return const Scaffold(body: Center(child: Text("Not signed in")));
    }

    final q = FirebaseFirestore.instance
        .collection("chats")
        .where("participants", arrayContains: uid)
        // .orderBy("lastTs", descending: true) // re-enable after index deploy
        .limit(200);

    return Scaffold(
      appBar: AppBar(title: const Text("Chats")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createBridgeGroupDialog,
        icon: const Icon(Icons.groups_2_outlined),
        label: const Text("Bridge group"),
      ),
      body: StreamBuilder<List<PartyMemberEntry>>(
        stream: PartyService.instance.watchMyPartyEntries(),
        builder: (context, partySnap) {
          final partyUids = partySnap.data?.map((e) => e.otherUid).toSet() ?? <String>{};

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            key: ValueKey<int>(_reloadKey),
            stream: q.snapshots(),
            builder: (context, snap) {
          if (snap.connectionState == ConnectionState.active ||
              snap.connectionState == ConnectionState.done) {
            _markLoaded();
          }

          if (snap.connectionState == ConnectionState.waiting) {
            if (_showLoadTimeout) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.inbox_outlined, size: 34),
                      const SizedBox(height: 10),
                      const Text(
                        "Inbox is taking longer than expected.",
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Check connectivity and retry.",
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _retryLoad,
                        icon: const Icon(Icons.refresh),
                        label: const Text("Retry"),
                      ),
                    ],
                  ),
                ),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Error: ${snap.error}", textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _retryLoad,
                      icon: const Icon(Icons.refresh),
                      label: const Text("Retry"),
                    ),
                  ],
                ),
              ),
            );
          }
          final docs = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

          final visible = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          for (final doc in docs) {
            final data = doc.data();
            final isGroup = _isGroupChat(data);
            final otherUid = _deriveOtherUid(data, uid);
            final isParty = otherUid.isNotEmpty && partyUids.contains(otherUid);
            final incomingRequest = _isIncomingChatRequest(data, uid);

            if (!isGroup) {
              if (otherUid.isEmpty) continue;
              if (!isParty && !incomingRequest) {
                // Hide non-party history threads and clean old empty ones.
                // ignore: discarded_futures
                _cleanupIfNoActivity(chatId: doc.id, data: data);
                continue;
              }
            }

            visible.add(doc);
          }

          visible.sort((a, b) {
            final ad = _readTs(a.data(), const ["updatedAt", "lastTs", "createdAt"]);
            final bd = _readTs(b.data(), const ["updatedAt", "lastTs", "createdAt"]);
            if (ad == null && bd == null) return 0;
            if (ad == null) return 1;
            if (bd == null) return -1;
            return bd.compareTo(ad);
          });

          final unreadCount = visible.where((d) => _isUnread(d.data(), uid)).length;
          final requestsCount = visible.where((d) => _isIncomingChatRequest(d.data(), uid)).length;

          final filtered = visible.where((doc) {
            if (_selectedFilterIndex == 1) return _isUnread(doc.data(), uid);
            if (_selectedFilterIndex == 2) return _isIncomingChatRequest(doc.data(), uid);
            return true;
          }).toList();

          if (visible.isEmpty) {
            return const Center(child: Text("No Party-linked chats yet"));
          }

          return Column(
            children: [
              if (requestsCount > 0)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "$requestsCount new chat request${requestsCount == 1 ? "" : "s"} need attention.",
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<int>(
                        segments: <ButtonSegment<int>>[
                          const ButtonSegment<int>(value: 0, label: Text("All")),
                          ButtonSegment<int>(value: 1, label: Text("Unread ($unreadCount)")),
                          ButtonSegment<int>(value: 2, label: Text("Requests ($requestsCount)")),
                        ],
                        selected: <int>{_selectedFilterIndex},
                        onSelectionChanged: (next) {
                          if (next.isEmpty) return;
                          setState(() => _selectedFilterIndex = next.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = filtered[i].data();
                    final chatId = filtered[i].id;
                    final isGroup = _isGroupChat(d);
                    final participants = _participants(d);
                    final otherUid = _deriveOtherUid(d, uid);
                    final ownerUid = (d["ownerUid"] ?? d["moderatorUid"] ?? "").toString().trim();
                    final isOwner = ownerUid.isNotEmpty && ownerUid == uid;
                    final isParty = otherUid.isNotEmpty && partyUids.contains(otherUid);
                    final unread = _isUnread(d, uid);
                    final incomingRequest = _isIncomingChatRequest(d, uid);

                    final title = _chatTitle(d, chatId, uid);
                    final subtitle = _chatSubtitle(d, uid, isParty: isParty);

                    return ListTile(
                      leading: CircleAvatar(
                        child: Icon(
                          isGroup ? Icons.groups_2_outlined : (isParty ? Icons.group_outlined : Icons.chat_bubble_outline),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          if (incomingRequest)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.error,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                "REQUEST",
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onError,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            )
                          else if (unread)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                "NEW",
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onPrimary,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: (isGroup && isOwner)
                          ? IconButton(
                              tooltip: "Manage members",
                              icon: const Icon(Icons.manage_accounts_outlined),
                              onPressed: () {
                                _manageGroupDialog(
                                  chatId: chatId,
                                  myUid: uid,
                                  participants: participants,
                                );
                              },
                            )
                          : null,
                      onTap: () {
                        final openWithUid = otherUid.isNotEmpty
                            ? otherUid
                            : participants.firstWhere((p) => p != uid, orElse: () => uid);
                        if (openWithUid.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("This chat is missing participant data."),
                            ),
                          );
                          return;
                        }

                        // ignore: discarded_futures
                        _pushWithHelpContext(
                          context,
                          contextKey: "chats:thread",
                          page: ChatThreadScreen(
                            chatId: chatId,
                            otherUid: openWithUid,
                            otherName: isGroup ? title : null,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
            },
          );
        },
      ),
    );
  }
}
