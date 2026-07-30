import "dart:async";

import "package:firebase_auth/firebase_auth.dart";

import "package:prox/services/chat/chat_gate_service.dart";

class ChatSessionLifecycleService {
  ChatSessionLifecycleService._();
  static final ChatSessionLifecycleService instance = ChatSessionLifecycleService._();

  Timer? _tick;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    await _runOnce();
    _tick = Timer.periodic(const Duration(seconds: 45), (_) {
      // ignore: discarded_futures
      _runOnce();
    });
  }

  Future<void> stop() async {
    _tick?.cancel();
    _tick = null;
    _started = false;
  }

  Future<void> _runOnce() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.trim().isEmpty) return;

    try {
      await ChatGateService.instance.enforceExpiredIncomingRequestsIfNeeded(forUid: uid);
      await ChatGateService.instance.enforceChatLifecycleForUid(forUid: uid);
    } catch (_) {
      // Best-effort maintenance only.
    }
  }
}
