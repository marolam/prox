import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prox/models/support_ticket_draft.dart';

class SupportTicketQueue extends ChangeNotifier {
  SupportTicketQueue._({String Function()? ownerId}) : _ownerId = ownerId;
  @visibleForTesting
  factory SupportTicketQueue.forTesting({required String Function() ownerId}) =>
      SupportTicketQueue._(ownerId: ownerId);
  static final SupportTicketQueue instance = SupportTicketQueue._();
  final String Function()? _ownerId;
  final Map<String, SupportTicketDraft> _drafts = {};
  final StreamController<List<SupportTicketDraft>> _controller =
      StreamController.broadcast();
  StreamSubscription<User?>? _auth;
  String? _owner;
  Future<void>? _loading;
  Future<void> _pendingWrite = Future.value();
  String? lastError;
  final Set<String> _deletedOwners = {};

  Future<void> clearForUser(String uid) async {
    _deletedOwners.add(uid);
    await _pendingWrite;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove('support.drafts.v1.$uid'))
      throw StateError('Could not remove local drafts');
    if (_owner == uid) {
      _drafts.clear();
      _emit();
    }
  }

  String get _currentOwner {
    final ownerId = _ownerId;
    if (ownerId != null) return ownerId();
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    } catch (_) {
      return 'guest';
    }
  }

  Stream<List<SupportTicketDraft>> watchDrafts() async* {
    await ensureLoaded();
    yield drafts;
    yield* _controller.stream;
  }

  List<SupportTicketDraft> get drafts {
    if (_owner != _currentOwner || _deletedOwners.contains(_owner)) return [];
    return _drafts.values.toList()..sort(
      (a, b) =>
          (b.updatedAt ?? b.createdAt).compareTo(a.updatedAt ?? a.createdAt),
    );
  }

  Future<void> ensureLoaded() {
    if (_ownerId == null && _auth == null) {
      try {
        _auth = FirebaseAuth.instance.authStateChanges().listen((_) {
          if (_owner != _currentOwner)
            unawaited(ensureLoaded().catchError((Object _) {}));
        });
      } catch (_) {
        /* Local guest drafts also work without Firebase. */
      }
    }
    final owner = _currentOwner;
    if (_owner == owner && _loading != null) return _loading!;
    _owner = owner;
    _drafts.clear();
    scheduleMicrotask(_emit);
    return _loading = _load(owner);
  }

  Future<void> _load(String owner) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('support.drafts.v1.$owner');
      final rows = raw == null ? <dynamic>[] : jsonDecode(raw) as List<dynamic>;
      final restored = <String, SupportTicketDraft>{};
      for (final row in rows) {
        if (row is! Map<String, dynamic>) continue;
        final createdAt = DateTime.tryParse('${row['createdAt']}');
        final id = row['id'];
        if (createdAt == null || id is! String || id.isEmpty) continue;
        restored[id] = SupportTicketDraft(
          id: id,
          subject: row['subject'] as String? ?? '',
          message: row['message'] as String? ?? '',
          createdAt: createdAt,
          updatedAt: DateTime.tryParse('${row['updatedAt']}'),
        );
      }
      if (_owner != owner || _deletedOwners.contains(owner)) return;
      _drafts
        ..clear()
        ..addAll(restored);
      lastError = null;
      _emit();
    } catch (_) {
      if (_owner == owner) {
        lastError = 'Saved drafts could not be loaded. Retry before editing.';
        _loading = null;
        _emit();
      }
      rethrow;
    }
  }

  Future<void> upsertDraft(SupportTicketDraft draft) async {
    final owner = _currentOwner;
    await ensureLoaded();
    if (_owner != owner || _currentOwner != owner)
      throw StateError('Account changed');
    await _persist(
      owner,
      (next) => next[draft.id] = draft.copyWith(updatedAt: DateTime.now()),
    );
  }

  Future<void> removeDraft(String draftId) async {
    final owner = _currentOwner;
    await ensureLoaded();
    if (_owner != owner || _currentOwner != owner)
      throw StateError('Account changed');
    await _persist(owner, (next) => next.remove(draftId));
  }

  Future<void> _persist(
    String owner,
    void Function(Map<String, SupportTicketDraft>) mutate,
  ) async {
    final write = _pendingWrite.then((_) async {
      if (_deletedOwners.contains(owner)) throw StateError('Account deleted');
      if (_owner != owner || _currentOwner != owner)
        throw StateError('Account changed');
      final next = {..._drafts};
      mutate(next);
      final encoded = jsonEncode(
        next.values
            .map(
              (d) => {
                'id': d.id,
                'subject': d.subject,
                'message': d.message,
                'createdAt': d.createdAt.toIso8601String(),
                'updatedAt': d.updatedAt?.toIso8601String(),
              },
            )
            .toList(),
      );
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString('support.drafts.v1.$owner', encoded))
        throw StateError('Draft storage unavailable');
      if (_owner == owner) {
        _drafts
          ..clear()
          ..addAll(next);
        lastError = null;
        _emit();
      }
    });
    _pendingWrite = write.catchError((Object _) {});
    try {
      await write;
    } catch (_) {
      if (_owner == owner) {
        lastError = 'Draft changes could not be saved. Please retry.';
        _emit();
      }
      rethrow;
    }
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(drafts);
    notifyListeners();
  }

  @override
  void dispose() {
    _auth?.cancel();
    _controller.close();
    super.dispose();
  }
}
