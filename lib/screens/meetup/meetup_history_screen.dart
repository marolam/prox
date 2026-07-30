import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "package:prox/services/now_feed_cleanup_service.dart";
import "package:prox/services/party_service.dart";
import "package:prox/services/user_profile_service.dart";

class MeetupHistoryScreen extends StatefulWidget {
  const MeetupHistoryScreen({super.key});

  @override
  State<MeetupHistoryScreen> createState() => _MeetupHistoryScreenState();
}

class _MeetupHistoryScreenState extends State<MeetupHistoryScreen> {
  static const Duration _completedRetention = Duration(hours: 24);
  static const Duration _staleRetention = Duration(hours: 12);
  static const Duration _autoClosePendingAfter = Duration(hours: 12);
  static const Duration _autoCloseLiveAfter = Duration(hours: 24);

  final Set<String> _deleteInFlight = <String>{};
  final Set<String> _autoCloseInFlight = <String>{};
  final Set<String> _cancelInFlight = <String>{};
  bool _manualCleanupRunning = false;
  String _meetupStreamUid = "";
  Stream<QuerySnapshot<Map<String, dynamic>>>? _meetupsAsAStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _meetupsAsBStream;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _runAutoCleanup();
  }

  Future<void> _runAutoCleanup() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.trim().isEmpty) return;
    await NowFeedCleanupService.instance.pruneAutoIfDue(uid);
  }

  Future<void> _runManualCleanup() async {
    if (_manualCleanupRunning) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.trim().isEmpty) return;

    setState(() => _manualCleanupRunning = true);
    try {
      final result = await NowFeedCleanupService.instance.pruneNow(uid);
      if (!mounted) return;
      final msg = result.totalDeleted == 0
          ? "Nothing stale to clear."
          : "Cleared ${result.meetupsDeleted} meetups and ${result.matchesDeleted} matches.";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not clear stale items right now.")),
      );
    } finally {
      if (mounted) setState(() => _manualCleanupRunning = false);
    }
  }

  void _ensureMeetupStreams(String uid) {
    if (uid == _meetupStreamUid && _meetupsAsAStream != null && _meetupsAsBStream != null) {
      return;
    }

    _meetupStreamUid = uid;
    final meetups = FirebaseFirestore.instance.collection("meetups");
    _meetupsAsAStream = meetups.where("aUid", isEqualTo: uid).snapshots();
    _meetupsAsBStream = meetups.where("bUid", isEqualTo: uid).snapshots();
  }

  String _otherUid(Map<String, dynamic> d, String me) {
    final a = (d["aUid"] ?? "").toString().trim();
    final b = (d["bUid"] ?? "").toString().trim();
    if (a == me) return b;
    if (b == me) return a;
    return a.isNotEmpty ? a : b;
  }

  bool _isLive(String status) => status == "live" || status == "completed";
  bool _isCompleted(String status) => status == "completed";
  bool _isPending(String status) => status == "requested" || status == "accepted";

  bool _nothingTranspired(String status) {
    return status.isEmpty ||
        status == "requested" ||
        status == "pending" ||
        status == "expired" ||
        status == "declined" ||
        status == "cancelled";
  }

  DateTime? _dateFrom(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  String _uidFallback(String uid) {
    final s = uid.trim();
    if (s.isEmpty) return "Prox user";
    final n = s.length >= 6 ? 6 : s.length;
    return "User ${s.substring(0, n)}";
  }

  bool _shouldHideForPrivacy({
    required Map<String, dynamic> d,
    required bool partyLinked,
    required DateTime now,
  }) {
    if (partyLinked) return false;

    final status = (d["status"] ?? "").toString().trim();
    final completedAt = _dateFrom(d["completedAt"]);
    final updatedAt = _dateFrom(d["updatedAt"]);

    if (status == "completed" && completedAt != null) {
      return now.difference(completedAt) > _completedRetention;
    }

    if (status == "expired" || status == "declined" || status == "cancelled") {
      if (updatedAt != null) {
        return now.difference(updatedAt) > _staleRetention;
      }
    }

    return false;
  }

  Future<void> _deleteStale(String id) async {
    if (_deleteInFlight.contains(id)) return;
    _deleteInFlight.add(id);
    try {
      await FirebaseFirestore.instance.collection("meetups").doc(id).delete();
    } catch (_) {
      // Best-effort privacy cleanup only.
    } finally {
      _deleteInFlight.remove(id);
    }
  }

  Future<void> _cancelPendingMeetup({
    required String meetupId,
    required String status,
  }) async {
    if (!_isPending(status)) return;
    if (_cancelInFlight.contains(meetupId)) return;

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Cancel pending meetup?"),
        content: const Text("This marks the meetup as cancelled for both participants."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Keep")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Cancel meetup")),
        ],
      ),
    );
    if (ok != true) return;

    _cancelInFlight.add(meetupId);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
      await FirebaseFirestore.instance.collection("meetups").doc(meetupId).set(
        <String, Object?>{
          "status": "cancelled",
          "cancelledBy": uid,
          "cancelledAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pending meetup cancelled.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't cancel meetup: $e")),
      );
    } finally {
      _cancelInFlight.remove(meetupId);
    }
  }

  Future<void> _autoCloseMeetupIfNeeded({
    required String meetupId,
    required Map<String, dynamic> d,
  }) async {
    if (_autoCloseInFlight.contains(meetupId)) return;

    final String status = (d["status"] ?? "").toString().trim();
    if (status == "completed" || status == "cancelled" || status == "expired" || status == "declined") {
      return;
    }

    final DateTime now = DateTime.now();
    final DateTime? createdAt = _dateFrom(d["createdAt"]);
    final DateTime? requestedAt = _dateFrom(d["requestedAt"]);
    final DateTime? startedAt = _dateFrom(d["startedAt"]);
    final DateTime? updatedAt = _dateFrom(d["updatedAt"]);
    final DateTime base = startedAt ?? requestedAt ?? createdAt ?? updatedAt ?? now;

    final Duration age = now.difference(base);
    final bool shouldAutoClose = _isPending(status)
        ? age > _autoClosePendingAfter
        : (status == "live" && age > _autoCloseLiveAfter);
    if (!shouldAutoClose) return;

    _autoCloseInFlight.add(meetupId);
    try {
      await FirebaseFirestore.instance.collection("meetups").doc(meetupId).set(
        <String, Object?>{
          "status": "auto_closed",
          "autoClosedAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // Best-effort safety close.
    } finally {
      _autoCloseInFlight.remove(meetupId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    final cs = Theme.of(context).colorScheme;

    if (uid.isEmpty) {
      return const Scaffold(
        body: Center(child: Text("Sign in to view meetups.")),
      );
    }

    _ensureMeetupStreams(uid);
    final aMeetupsStream = _meetupsAsAStream ?? const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    final bMeetupsStream = _meetupsAsBStream ?? const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Meetups"),
        actions: [
          IconButton(
            tooltip: "Clear stale now",
            onPressed: _manualCleanupRunning ? null : _runManualCleanup,
            icon: _manualCleanupRunning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_delete_outlined),
          ),
        ],
      ),
      body: StreamBuilder<List<PartyMemberEntry>>(
        stream: PartyService.instance.watchMyPartyEntries(),
        builder: (context, partySnap) {
          final partyUids = partySnap.data?.map((e) => e.otherUid).toSet() ?? <String>{};

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: aMeetupsStream,
            builder: (context, aSnap) {
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: bMeetupsStream,
                builder: (context, bSnap) {
                  final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
                    for (final d in (aSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])) d.id: d,
                    for (final d in (bSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])) d.id: d,
                  };

                  final docs = byId.values.toList(growable: true)
                    ..sort((x, y) {
                      final xd = x.data();
                      final yd = y.data();
                      final xTs = (xd["updatedAt"] is Timestamp)
                          ? (xd["updatedAt"] as Timestamp).millisecondsSinceEpoch
                          : 0;
                      final yTs = (yd["updatedAt"] is Timestamp)
                          ? (yd["updatedAt"] as Timestamp).millisecondsSinceEpoch
                          : 0;
                      return yTs.compareTo(xTs);
                    });

                  final now = DateTime.now();
                  final visible = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                  for (final doc in docs) {
                    final data = doc.data();
                    final other = _otherUid(data, uid);
                    final inParty = partyUids.contains(other);
                    final status = (data["status"] ?? "").toString().trim();

                    if (!inParty) {
                      // History is Party-only. Clean up non-party stale/no-outcome meetups.
                      final shouldDelete = _nothingTranspired(status) ||
                          _shouldHideForPrivacy(
                            d: data,
                            partyLinked: false,
                            now: now,
                          );
                      if (shouldDelete) {
                        // ignore: discarded_futures
                        _deleteStale(doc.id);
                      }
                      continue;
                    }

                    final hide = _shouldHideForPrivacy(
                      d: data,
                      partyLinked: inParty,
                      now: now,
                    );

                    if (hide) {
                      // Best-effort cleanup to keep history privacy-first.
                      // ignore: discarded_futures
                      _deleteStale(doc.id);
                      continue;
                    }

                    // Keep meetups from lingering forever when they are never completed.
                    // ignore: discarded_futures
                    _autoCloseMeetupIfNeeded(meetupId: doc.id, d: data);

                    visible.add(doc);
                  }

                  final completed = visible.where((doc) {
                    final s = (doc.data()["status"] ?? "").toString().trim();
                    return _isCompleted(s);
                  }).toList(growable: false);
                  final incomplete = visible.where((doc) {
                    final s = (doc.data()["status"] ?? "").toString().trim();
                    return !_isCompleted(s);
                  }).toList(growable: false);

                  if (visible.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          "No meetups yet. Open a chat and request a meetup to start.",
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                    children: [
                      _sectionHeader(context, "Incomplete Meetups", incomplete.length),
                      const SizedBox(height: 8),
                      if (incomplete.isEmpty)
                        _emptySectionCard(context, "No incomplete meetups right now.")
                      else
                        ...incomplete.map((doc) => _meetupCard(
                              context,
                              uid: uid,
                              cs: cs,
                              doc: doc,
                            )),
                      const SizedBox(height: 14),
                      _sectionHeader(context, "Completed Meetups", completed.length),
                      const SizedBox(height: 8),
                      if (completed.isEmpty)
                        _emptySectionCard(context, "No completed meetups yet.")
                      else
                        ...completed.map((doc) => _meetupCard(
                              context,
                              uid: uid,
                              cs: cs,
                              doc: doc,
                            )),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
      backgroundColor: cs.surface,
    );
  }

  Widget _sectionHeader(BuildContext context, String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(width: 8),
        _pill(context, "$count"),
      ],
    );
  }

  Widget _emptySectionCard(BuildContext context, String text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Widget _meetupCard(
    BuildContext context, {
    required String uid,
    required ColorScheme cs,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
  }) {
    final d = doc.data();
    final chatId = (d["chatId"] ?? doc.id).toString();
    final status = (d["status"] ?? "").toString().trim();
    final otherUid = _otherUid(d, uid);
    final locStatus = (d["locationStatus"] ?? "none").toString().trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              otherUid.isEmpty ? "Meetup" : "Meetup with",
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (otherUid.isNotEmpty)
              StreamBuilder<UserProfile?>(
                stream: UserProfileService.instance.watchProfile(otherUid),
                builder: (context, psnap) {
                  final p = psnap.data;
                  final display = (p?.displayName ?? "").trim();
                  final title = display.isNotEmpty ? display : _uidFallback(otherUid);
                  return Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                },
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(context, "Status: ${status.isEmpty ? "unknown" : status}"),
                _pill(context, "Location: $locStatus"),
                if (_isCompleted(status)) _myRatingFlag(context, meetupId: chatId, myUid: uid),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushNamed(
                        "/chat",
                        arguments: {"chatId": chatId, "otherUid": otherUid},
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text("Open chat"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      final route = _isLive(status) ? "/meetup_live" : "/meetup_plan";
                      Navigator.of(context).pushNamed(
                        route,
                        arguments: {
                          "chatId": chatId,
                          "otherUid": otherUid,
                          "meetupId": chatId,
                        },
                      );
                    },
                    icon: Icon(_isLive(status) ? Icons.map_outlined : Icons.edit_location_alt),
                    label: Text(_isLive(status) ? "Open live" : "Open planner"),
                  ),
                ),
              ],
            ),
            if (_isPending(status)) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _cancelInFlight.contains(chatId)
                      ? null
                      : () => _cancelPendingMeetup(meetupId: chatId, status: status),
                  icon: _cancelInFlight.contains(chatId)
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cancel_outlined),
                  label: const Text("Cancel pending meetup"),
                ),
              ),
            ],
            const SizedBox(height: 10),
            _MeetupNotesPanel(meetupId: chatId, myUid: uid),
          ],
        ),
      ),
    );
  }

  Widget _myRatingFlag(BuildContext context, {required String meetupId, required String myUid}) {
    final ref = FirebaseFirestore.instance.doc("ratings/$meetupId/entries/$myUid");
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        final hasRated = snap.data?.exists == true;
        return _pill(
          context,
          hasRated ? "Rated" : "Rating pending",
        );
      },
    );
  }

  Widget _pill(BuildContext context, String label) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _MeetupNotesPanel extends StatefulWidget {
  final String meetupId;
  final String myUid;

  const _MeetupNotesPanel({
    required this.meetupId,
    required this.myUid,
  });

  @override
  State<_MeetupNotesPanel> createState() => _MeetupNotesPanelState();
}

class _MeetupNotesPanelState extends State<_MeetupNotesPanel> {
  late final TextEditingController _ctrl;
  bool _sending = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance
          .collection("meetups")
          .doc(widget.meetupId)
          .collection("notes")
          .add(<String, Object?>{
        "uid": widget.myUid,
        "text": text,
        "createdAt": FieldValue.serverTimestamp(),
      });
      _ctrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't add note: $e")),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _editNote({required String noteId, required String currentText}) async {
    if (_editing) return;
    final ctrl = TextEditingController(text: currentText);
    final String? updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Edit note"),
        content: TextField(
          controller: ctrl,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text("Save")),
        ],
      ),
    );
    ctrl.dispose();

    if (updated == null || updated.trim().isEmpty || updated.trim() == currentText.trim()) return;

    setState(() => _editing = true);
    try {
      await FirebaseFirestore.instance
          .collection("meetups")
          .doc(widget.meetupId)
          .collection("notes")
          .doc(noteId)
          .set(
        <String, Object?>{
          "text": updated.trim(),
          "editedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't edit note: $e")),
      );
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _deleteNote({required String noteId}) async {
    if (_editing) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete note?"),
        content: const Text("This will remove this note from meetup history."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete")),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _editing = true);
    try {
      await FirebaseFirestore.instance
          .collection("meetups")
          .doc(widget.meetupId)
          .collection("notes")
          .doc(noteId)
          .delete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't delete note: $e")),
      );
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final notesRef = FirebaseFirestore.instance
        .collection("meetups")
        .doc(widget.meetupId)
        .collection("notes")
        .orderBy("createdAt", descending: true)
        .limit(20);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Meetup Notes",
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: notesRef.snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              if (docs.isEmpty) {
                return Text(
                  "No notes yet. Add reminders or next steps.",
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                );
              }

              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i].data();
                    final noteId = docs[i].id;
                    final text = (d["text"] ?? "").toString().trim();
                    final uid = (d["uid"] ?? "").toString().trim();
                    final mine = uid == widget.myUid;
                    if (text.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              "${mine ? "You" : "Them"}: $text",
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          if (mine) ...[
                            IconButton(
                              tooltip: "Edit note",
                              iconSize: 16,
                              visualDensity: VisualDensity.compact,
                              onPressed: _editing ? null : () => _editNote(noteId: noteId, currentText: text),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: "Delete note",
                              iconSize: 16,
                              visualDensity: VisualDensity.compact,
                              onPressed: _editing ? null : () => _deleteNote(noteId: noteId),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: "Add note",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _sending ? null : _send,
                child: _sending
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text("Add"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
