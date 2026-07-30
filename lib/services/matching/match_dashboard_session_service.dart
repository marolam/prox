import "dart:async";

import "package:flutter/foundation.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/services/presence_writer.dart";

enum MatchDashboardSessionState {
  pendingDecision,
  accepted,
  declined,
  timedOut,
  cancelled,
  completed,
}

class MatchDashboardSession {
  final String chatId;
  final String otherUid;
  final MatchingModeKind modeKind;
  final NormalMatchMode normalMode;
  final DateTime startedAt;
  final DateTime decisionDeadline;
  final MatchDashboardSessionState state;

  const MatchDashboardSession({
    required this.chatId,
    required this.otherUid,
    required this.modeKind,
    required this.normalMode,
    required this.startedAt,
    required this.decisionDeadline,
    required this.state,
  });

  bool get isActive =>
      state == MatchDashboardSessionState.pendingDecision ||
      state == MatchDashboardSessionState.accepted;

  MatchDashboardSession copyWith({
    String? chatId,
    String? otherUid,
    MatchingModeKind? modeKind,
    NormalMatchMode? normalMode,
    DateTime? startedAt,
    DateTime? decisionDeadline,
    MatchDashboardSessionState? state,
  }) {
    return MatchDashboardSession(
      chatId: chatId ?? this.chatId,
      otherUid: otherUid ?? this.otherUid,
      modeKind: modeKind ?? this.modeKind,
      normalMode: normalMode ?? this.normalMode,
      startedAt: startedAt ?? this.startedAt,
      decisionDeadline: decisionDeadline ?? this.decisionDeadline,
      state: state ?? this.state,
    );
  }
}

class MatchDashboardSessionService {
  MatchDashboardSessionService._();
  static final MatchDashboardSessionService instance =
      MatchDashboardSessionService._();

  final ValueNotifier<MatchDashboardSession?> _session =
      ValueNotifier<MatchDashboardSession?>(null);
  bool _meetupCadenceEnabled = false;
    final Map<String, DateTime> _autoLaunchSuppressedUntilByOtherUid =
      <String, DateTime>{};

    static const Duration _timeoutSuppressDuration = Duration(minutes: 10);
    static const Duration _cancelSuppressDuration = Duration(minutes: 5);
    static const Duration _declineSuppressDuration = Duration(minutes: 3);

  ValueListenable<MatchDashboardSession?> get sessionListenable => _session;
  MatchDashboardSession? get current => _session.value;

  bool get hasActiveSession => _session.value?.isActive ?? false;
  bool get shouldSuspendDiscovery => hasActiveSession;

  bool isAutoLaunchSuppressedForOtherUid(String otherUid) {
    final uid = otherUid.trim();
    if (uid.isEmpty) return false;
    _pruneSuppression();
    final until = _autoLaunchSuppressedUntilByOtherUid[uid];
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  Duration? autoLaunchSuppressionLeftForOtherUid(String otherUid) {
    final uid = otherUid.trim();
    if (uid.isEmpty) return null;
    _pruneSuppression();
    final until = _autoLaunchSuppressedUntilByOtherUid[uid];
    if (until == null) return null;
    final left = until.difference(DateTime.now());
    if (left <= Duration.zero) return null;
    return left;
  }

  void startSession({
    required String chatId,
    required String otherUid,
    required MatchingModeKind modeKind,
    required NormalMatchMode normalMode,
    Duration decisionWindow = const Duration(minutes: 10),
  }) {
    final existing = _session.value;
    if (existing != null && existing.isActive) {
      // Keep active flow stable instead of replacing it mid-session.
      return;
    }

    final now = DateTime.now();
    _session.value = MatchDashboardSession(
      chatId: chatId,
      otherUid: otherUid,
      modeKind: modeKind,
      normalMode: normalMode,
      startedAt: now,
      decisionDeadline: now.add(decisionWindow),
      state: MatchDashboardSessionState.pendingDecision,
    );

    PresenceWriter.instance.beginCriticalUiSection(
      reason: "match_dashboard_session",
    );
    _setMeetupCadence(enabled: false);
  }

  void markAccepted() {
    final s = _session.value;
    if (s == null) return;
    if (s.state != MatchDashboardSessionState.pendingDecision) return;
    _session.value = s.copyWith(state: MatchDashboardSessionState.accepted);
    _setMeetupCadence(enabled: true);
  }

  void markDeclined() {
    final s = _session.value;
    if (s == null) return;
    if (s.state != MatchDashboardSessionState.pendingDecision) return;
    _suppressAutoLaunchForSession(s, _declineSuppressDuration);
    _endSession(MatchDashboardSessionState.declined);
  }

  void markTimedOut() {
    final s = _session.value;
    if (s == null) return;
    if (s.state != MatchDashboardSessionState.pendingDecision) return;
    _suppressAutoLaunchForSession(s, _timeoutSuppressDuration);
    _endSession(MatchDashboardSessionState.timedOut);
  }

  void markCancelled() {
    final s = _session.value;
    if (s == null) return;
    if (s.state != MatchDashboardSessionState.pendingDecision &&
        s.state != MatchDashboardSessionState.accepted) {
      return;
    }
    _suppressAutoLaunchForSession(s, _cancelSuppressDuration);
    _endSession(MatchDashboardSessionState.cancelled);
  }

  void markCompleted() {
    final s = _session.value;
    if (s == null) return;
    if (s.state != MatchDashboardSessionState.accepted) return;
    _endSession(MatchDashboardSessionState.completed);
  }

  void clear() => _endSession(MatchDashboardSessionState.completed, clearOnly: true);

  void _suppressAutoLaunchForSession(MatchDashboardSession session, Duration duration) {
    final other = session.otherUid.trim();
    if (other.isEmpty) return;
    _pruneSuppression();
    final now = DateTime.now();
    final nextUntil = now.add(duration);
    final prev = _autoLaunchSuppressedUntilByOtherUid[other];
    if (prev == null || nextUntil.isAfter(prev)) {
      _autoLaunchSuppressedUntilByOtherUid[other] = nextUntil;
    }
  }

  void _pruneSuppression() {
    if (_autoLaunchSuppressedUntilByOtherUid.isEmpty) return;
    final now = DateTime.now();
    final expired = <String>[];
    _autoLaunchSuppressedUntilByOtherUid.forEach((uid, until) {
      if (!now.isBefore(until)) {
        expired.add(uid);
      }
    });
    for (final uid in expired) {
      _autoLaunchSuppressedUntilByOtherUid.remove(uid);
    }
  }

  void _endSession(
    MatchDashboardSessionState finalState, {
    bool clearOnly = false,
  }) {
    final s = _session.value;
    if (s != null && !clearOnly) {
      _session.value = s.copyWith(state: finalState);
    }
    _session.value = null;
    _setMeetupCadence(enabled: false);
    PresenceWriter.instance.endCriticalUiSection(
      reason: "match_dashboard_session_end",
    );
  }

  void _setMeetupCadence({required bool enabled}) {
    if (_meetupCadenceEnabled == enabled) return;
    _meetupCadenceEnabled = enabled;
    if (enabled) {
      unawaited(
        PresenceWriter.instance.beginMeetupMode(
          reason: "match_dashboard_accepted",
        ),
      );
      return;
    }
    unawaited(
      PresenceWriter.instance.endMeetupMode(
        reason: "match_dashboard_idle",
      ),
    );
  }
}
