import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:prox/models/user_settings.dart';

class ChatRequestPolicy {
  static const activeWindow = Duration(seconds: 60);
  static const standardWindow = Duration(hours: 24);

  static Duration creationWindow(
    MatchingModeKind mode,
    Map<String, dynamic> recipient,
    DateTime now,
  ) {
    final seen = recipient['ts'];
    final expiry = recipient['expiresAt'];
    final fresh =
        seen is Timestamp &&
        expiry is Timestamp &&
        expiry.toDate().isAfter(now) &&
        now.difference(seen.toDate()) >= const Duration(minutes: -1) &&
        now.difference(seen.toDate()) <= const Duration(minutes: 3);
    return mode == MatchingModeKind.normal &&
            recipient['modeKind'] == 'normal' &&
            recipient['normalMode'] == 'active' &&
            fresh
        ? activeWindow
        : standardWindow;
  }

  static bool isActiveRequest(Map<String, dynamic> gate) =>
      gate['modeKind'] == 'normal' &&
      gate['responseWindowSeconds'] == activeWindow.inSeconds;

  static DateTime? deadline(Map<String, dynamic> gate) {
    final requestedAt = gate['requestedAt'];
    if (requestedAt is! Timestamp) return null;
    // Legacy untagged requests never prove that the recipient opted into Active.
    return requestedAt.toDate().add(
      isActiveRequest(gate) ? activeWindow : standardWindow,
    );
  }

  static bool canRenew(Map<String, dynamic> chat) {
    final gate = chat['chatGate'];
    return chat['closedAt'] == null &&
        gate is Map &&
        gate['status'] == 'expired' &&
        gate['expiredBySystem'] == true &&
        gate['acceptedAt'] == null &&
        gate['declinedAt'] == null &&
        (gate['acceptedBy'] == null || gate['acceptedBy'] == '') &&
        (gate['declinedBy'] == null || gate['declinedBy'] == '');
  }
}
