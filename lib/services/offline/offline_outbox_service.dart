import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prox/services/meetup_service.dart';

/// Durable, account-scoped retries for explicit user actions.
class OfflineOutboxService extends ChangeNotifier {
  OfflineOutboxService._();
  static final OfflineOutboxService instance = OfflineOutboxService._();
  bool _started = false;
  bool _flushing = false;
  Future<void> _storage = Future<void>.value();
  final Set<String> _deletedUsers = <String>{};
  int pendingCount = 0;
  Object? lastError;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    FirebaseAuth.instance.authStateChanges().listen((_) {
      pendingCount = 0;
      unawaited(flush());
    });
    Connectivity().onConnectivityChanged.listen((status) {
      if (!status.contains(ConnectivityResult.none)) unawaited(flush());
    });
    Timer.periodic(const Duration(seconds: 30), (_) => unawaited(flush()));
    await flush();
  }

  String _key(String uid) => 'prox_outbox_v1_$uid';

  Future<void> _mutate(String uid, void Function(Map<String, dynamic>) action) {
    final operation = _storage.catchError((Object _) {}).then((_) async {
      if (_deletedUsers.contains(uid)) return;
      final prefs = await SharedPreferences.getInstance();
      if (_deletedUsers.contains(uid)) return;
      final raw = prefs.getString(_key(uid));
      final entries = raw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
      action(entries);
      if (!await prefs.setString(_key(uid), jsonEncode(entries))) {
        throw StateError('Unable to save pending changes.');
      }
      if (FirebaseAuth.instance.currentUser?.uid == uid) {
        pendingCount = entries.length;
        notifyListeners();
      }
    });
    _storage = operation;
    return operation;
  }

  Future<void> enqueueSet({
    required String docPath,
    required Map<String, Object?> data,
    String? idempotencyKey,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null ||
        !docPath.startsWith('users/$uid/party/') ||
        docPath.split('/').length != 4) {
      throw StateError('Only your own Party changes can be queued.');
    }
    jsonEncode(
      data,
    ); // Reject unsupported/sensitive Firestore sentinels before claiming success.
    await _enqueue(uid, idempotencyKey ?? docPath, {
      'kind': 'set',
      'path': docPath,
      'data': data,
    });
  }

  Future<void> enqueueConfirmArrival({
    required String meetupId,
    required String uid,
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid ||
        meetupId.isEmpty ||
        meetupId.contains('/')) {
      throw StateError('Sign in to queue this arrival.');
    }
    await _enqueue(uid, 'arrival_$meetupId', {
      'kind': 'arrival',
      'meetupId': meetupId,
    });
  }

  Future<void> _enqueue(
    String uid,
    String id,
    Map<String, Object?> item,
  ) async {
    await _mutate(uid, (entries) {
      if (entries.length >= 200 && !entries.containsKey(id))
        throw StateError('Pending changes are full. Reconnect first.');
      if (item['kind'] == 'arrival' && entries.containsKey(id)) return;
      entries[id] = {
        ...item,
        'queuedAt': DateTime.now().millisecondsSinceEpoch,
      };
    });
    unawaited(start());
  }

  Future<void> clearForUser(String uid) async {
    _deletedUsers.add(uid);
    final operation = _storage.catchError((Object _) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.remove(_key(uid))) {
        throw StateError('Unable to remove pending changes.');
      }
      pendingCount = 0;
      notifyListeners();
    });
    _storage = operation;
    await operation;
  }

  Future<void> flush() async {
    if (_flushing) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _deletedUsers.contains(uid)) return;
    _flushing = true;
    try {
      await _storage.catchError((Object _) {});
      if (_deletedUsers.contains(uid)) return;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(uid));
      final entries = raw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
      pendingCount = entries.length;
      for (final entry in entries.entries) {
        if (FirebaseAuth.instance.currentUser?.uid != uid ||
            _deletedUsers.contains(uid))
          break;
        final item = Map<String, dynamic>.from(entry.value as Map);
        final age =
            DateTime.now().millisecondsSinceEpoch -
            (item['queuedAt'] as num).toInt();
        if (item['kind'] == 'set') {
          if (age < const Duration(days: 7).inMilliseconds) {
            await FirebaseFirestore.instance
                .doc(item['path'] as String)
                .set(
                  Map<String, Object?>.from(item['data'] as Map),
                  SetOptions(merge: true),
                )
                .timeout(const Duration(seconds: 12));
          }
        } else if (item['kind'] == 'arrival' &&
            age < const Duration(hours: 2).inMilliseconds) {
          final result = await MeetupService.instance.confirmArrivalGuarded(
            meetupId: item['meetupId'] as String,
          );
          if ([
            ConfirmArrivalStatus.failed,
            ConfirmArrivalStatus.tooSoon,
            ConfirmArrivalStatus.notSignedIn,
          ].contains(result.status))
            break;
        }
        await _mutate(uid, (queue) {
          if ((queue[entry.key] as Map?)?['queuedAt'] == item['queuedAt'])
            queue.remove(entry.key);
        });
      }
      lastError = null;
    } catch (error) {
      lastError = error;
    } finally {
      _flushing = false;
      notifyListeners();
    }
  }
}
