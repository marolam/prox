import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ActionReceipt {
  const ActionReceipt({
    required this.kind,
    required this.title,
    required this.detail,
    required this.createdAt,
  });
  final String kind;
  final String title;
  final String detail;
  final DateTime createdAt;
}

class ActionReceiptService {
  ActionReceiptService._();
  static final ActionReceiptService instance = ActionReceiptService._();
  final StreamController<List<ActionReceipt>> _controller =
      StreamController.broadcast();
  final List<ActionReceipt> _items = [];
  String? _owner;
  Future<void>? _loading;
  Future<void> _pending = Future.value();
  final Set<String> _deletedOwners = {};

  Future<void> clearForUser(String uid) async {
    _deletedOwners.add(uid);
    await _pending;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove('action.receipts.v1.$uid'))
      throw StateError('Could not remove local receipts');
    if (_owner == uid) {
      _items.clear();
      _controller.add(const []);
    }
  }

  String get _uid {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    } catch (_) {
      return 'guest';
    }
  }

  Future<void> _load() {
    final uid = _uid;
    if (_owner == uid && _loading != null) return _loading!;
    _owner = uid;
    _items.clear();
    return _loading = _restore(uid);
  }

  Future<void> _restore(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('action.receipts.v1.$uid');
      final rows = raw == null ? <dynamic>[] : jsonDecode(raw) as List<dynamic>;
      if (_owner != uid || _uid != uid || _deletedOwners.contains(uid)) return;
      for (final row in rows.take(100)) {
        if (row is! Map<String, dynamic>) continue;
        final date = DateTime.tryParse('${row['createdAt']}');
        if (date == null) continue;
        _items.add(
          ActionReceipt(
            kind: '${row['kind'] ?? ''}',
            title: '${row['title'] ?? ''}',
            detail: '${row['detail'] ?? ''}',
            createdAt: date,
          ),
        );
      }
    } catch (_) {
      if (_owner == uid) {
        _owner = null;
        _loading = null;
      }
      rethrow;
    }
  }

  Stream<List<ActionReceipt>> watch() async* {
    await _load();
    yield List.unmodifiable(_items);
    yield* _controller.stream;
  }

  Future<void> add({
    required String kind,
    required String title,
    required String detail,
  }) {
    final uid = _uid;
    final work = _pending.then((_) async {
      if (_deletedOwners.contains(uid)) return;
      await _load();
      if (_uid != uid || _deletedOwners.contains(uid)) return;
      final next = [
        ActionReceipt(
          kind: kind,
          title: title,
          detail: detail,
          createdAt: DateTime.now().toUtc(),
        ),
        ..._items,
      ].take(100).toList();
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(
        'action.receipts.v1.$uid',
        jsonEncode(
          next
              .map(
                (r) => {
                  'kind': r.kind,
                  'title': r.title,
                  'detail': r.detail,
                  'createdAt': r.createdAt.toIso8601String(),
                },
              )
              .toList(),
        ),
      ))
        throw StateError('Receipt storage unavailable');
      if (_uid != uid || _owner != uid) return;
      _items
        ..clear()
        ..addAll(next);
      _controller.add(List.unmodifiable(_items));
    });
    // A local receipt must not turn a completed server action into a failed purchase.
    _pending = work.catchError((Object _) {});
    return _pending;
  }
}
