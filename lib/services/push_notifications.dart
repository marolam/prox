import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

import "package:prox/models/notification_item.dart";
import "package:prox/services/notification_copy.dart";
import "package:prox/services/notification_feed_service.dart";
import "package:prox/services/notification_router.dart";
import "package:prox/services/ttl/ttl_policy.dart";
import "package:prox/widgets/in_app_notification_banner.dart";

class PushNotifications {
  PushNotifications._();
  static final PushNotifications instance = PushNotifications._();

  final FirebaseMessaging _fm = FirebaseMessaging.instance;
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<String>? _tokenRefreshSub;

  bool _initialized = false;
  String? _currentUid;
  bool _disabledForSession = false;

  GlobalKey<NavigatorState>? _navigatorKey;
  bool _openHandlersInitialized = false;

  void registerNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
    if (kDebugMode) debugPrint("[Push] Registered navigator key.");
  }

  Future<void> initForUser(String uid) async {
    if (uid.isEmpty) return;
    if (_disabledForSession) {
      if (kDebugMode) debugPrint("[Push] Disabled for this app session.");
      return;
    }

    if (_initialized && _currentUid == uid) return;
    _currentUid = uid;

    await _requestPermission();

    try {
      final String? token = await _fm.getToken().timeout(const Duration(seconds: 8));
      if (token != null && token.isNotEmpty) {
        await _saveToken(uid, token);
      }
    } catch (e) {
      if (_isGmsBrokerIssue(e)) {
        _disabledForSession = true;
        if (kDebugMode) debugPrint("[Push] Disabled after broker security error: $e");
        return;
      }
      if (kDebugMode) debugPrint("[Push] getToken error: $e");
    }

    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _fm.onTokenRefresh.listen((newToken) async {
      final String current = _auth.currentUser?.uid ?? _currentUid ?? "";
      if (current.isEmpty) return;
      await _saveToken(current, newToken);
    });

    await _foregroundSub?.cancel();
    _foregroundSub = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    _initialized = true;
    if (kDebugMode) debugPrint("[Push] Initialized for uid=$uid");
  }

  Future<void> setupMessageOpenHandlers() async {
    if (_disabledForSession) return;
    if (_openHandlersInitialized) return;
    _openHandlersInitialized = true;

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      await handleRemoteMessage(message);
    });

    try {
      final RemoteMessage? initial = await _fm.getInitialMessage();
      if (initial != null) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await handleRemoteMessage(initial);
      }
    } catch (e) {
      if (_isGmsBrokerIssue(e)) {
        _disabledForSession = true;
        if (kDebugMode) debugPrint("[Push] Disabled after initial-message broker error: $e");
        return;
      }
      if (kDebugMode) debugPrint("[Push] getInitialMessage error: $e");
    }
  }

  Future<void> notifyBusinessHotLead({
    required String leadId,
    required int score,
  }) async {
    if (kDebugMode) {
      debugPrint("[Push] business hot lead leadId=$leadId score=$score");
    }
  }

  Future<void> _requestPermission() async {
    try {
      final settings = await _fm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: true,
      );
      if (kDebugMode) debugPrint("[Push] Permission: ${settings.authorizationStatus}");
    } catch (e) {
      if (_isGmsBrokerIssue(e)) {
        _disabledForSession = true;
        if (kDebugMode) debugPrint("[Push] Disabled after permission broker error: $e");
        return;
      }
      if (kDebugMode) debugPrint("[Push] Permission error: $e");
    }
  }

  bool _isGmsBrokerIssue(Object e) {
    final s = e.toString();
    return s.contains("Unknown calling package name 'com.google.android.gms'") ||
        s.contains("DEVELOPER_ERROR") ||
        (s.contains("SecurityException") && s.contains("GoogleApi"));
  }

  Future<void> _saveToken(String uid, String token) async {
    try {
      final docRef = _fs.collection("users").doc(uid).collection("deviceTokens").doc(token);
      await docRef.set(
        <String, Object?>{
          "token": token,
          "platform": _platform(),
          "createdAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
          "valid": true,
          "lastSeenAt": FieldValue.serverTimestamp(),
          "expiresAt": TTLPolicy.expiresAtFromNow(TTLPolicy.deviceToken),
          "build": const String.fromEnvironment("BUILD_FLAVOR", defaultValue: "dev"),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      if (kDebugMode) debugPrint("[Push] saveToken error: $e");
    }
  }

  Future<void> signOutCleanup(String uid) async {
    if (uid.isEmpty) return;
    try {
      final String? token = await _fm.getToken();
      if (token == null || token.isEmpty) return;

      final docRef = _fs.collection("users").doc(uid).collection("deviceTokens").doc(token);
      await docRef.set(
        <String, Object?>{
          "valid": false,
          "updatedAt": FieldValue.serverTimestamp(),
          "expiresAt": TTLPolicy.expiresAtFromNow(const Duration(days: 14)),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      if (kDebugMode) debugPrint("[Push] signOutCleanup error: $e");
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final item = _buildNotificationItemFromMessage(message, seen: false);

    // In-memory feed (no schema writes).
    NotificationFeedService.instance.add(item);

    // Foreground banner.
    unawaited(_showInAppBanner(item));
  }

  Future<void> handleRemoteMessage(RemoteMessage message) async {
    final ctx = _navigatorKey?.currentState?.context;
    if (ctx == null) {
      if (kDebugMode) debugPrint("[Push] Missing navigator context; ignoring open.");
      return;
    }

    final item = _buildNotificationItemFromMessage(message, seen: true);

    // Tap history (in-memory).
    NotificationFeedService.instance.add(item);

    final Map<String, dynamic>? data = item.data;
    if (data != null) {
      try {
        await _ensureChatArgsInData(data);
      } catch (e) {
        if (kDebugMode) debugPrint("[Push] normalize chat args error: $e");
      }
    }

    // FIX: handleTap may be sync (void). Do not await.
    NotificationRouter.instance.handleTap(ctx, item);
  }

  Future<void> _ensureChatArgsInData(Map<String, dynamic> data) async {
    final String chatId = (data["chatId"] ?? "").toString().trim();
    if (chatId.isEmpty) return;

    String otherUid = (data["otherUid"] ?? "").toString().trim();
    if (otherUid.isEmpty) otherUid = (data["peerUid"] ?? "").toString().trim();
    if (otherUid.isEmpty) otherUid = (data["partnerUid"] ?? "").toString().trim();

    if (otherUid.isNotEmpty) {
      data["otherUid"] = otherUid;
      return;
    }

    final String me = _auth.currentUser?.uid ?? _currentUid ?? "";
    if (me.isEmpty) return;

    final snap = await _fs.collection("chats").doc(chatId).get();
    final d = snap.data() ?? <String, dynamic>{};
    final p = d["participants"];

    String derived = "";
    if (p is List) {
      for (final x in p) {
        final s = (x ?? "").toString().trim();
        if (s.isNotEmpty && s != me) {
          derived = s;
          break;
        }
      }
    } else if (p is Map) {
      for (final k in p.keys) {
        final s = (k ?? "").toString().trim();
        if (s.isNotEmpty && s != me) {
          derived = s;
          break;
        }
      }
    }

    if (derived.isNotEmpty) {
      data["otherUid"] = derived;
    }
  }

  NotificationCopyKey _mapTypeToCopyKey(String type) {
    switch (type) {
      case "match":
        return NotificationCopyKey.match;
      case "message":
      case "chat_message":
      case "party_message":
      case "party_chat_request":
      case "chat_request":
        return NotificationCopyKey.message;
      case "meetup":
        return NotificationCopyKey.meetup;
      case "party":
        return NotificationCopyKey.party;
      default:
        return NotificationCopyKey.system;
    }
  }

  NotificationItem _buildNotificationItemFromMessage(
    RemoteMessage message, {
    required bool seen,
  }) {
    final Map<String, dynamic> data = Map<String, dynamic>.from(message.data);

    final String rawType = (data["type"] as String?) ?? "system";
    final bool chatRequest = (data["chatRequest"] ?? "false").toString().toLowerCase() == "true";
    final bool partyContext = (data["isPartyContext"] ?? "false").toString().toLowerCase() == "true";

    String type = rawType;
    if (rawType == "message" && chatRequest && partyContext) {
      type = "party_chat_request";
    } else if (rawType == "message" && chatRequest) {
      type = "chat_request";
    } else if (rawType == "message" && partyContext) {
      type = "party_message";
    }

    DateTime ts;
    final dynamic tsRaw = data["ts"];
    if (tsRaw is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(tsRaw);
    } else if (tsRaw is String) {
      final int? parsed = int.tryParse(tsRaw);
      ts = parsed != null ? DateTime.fromMillisecondsSinceEpoch(parsed) : DateTime.now();
    } else {
      ts = DateTime.now();
    }

    final NotificationCopyKey key = _mapTypeToCopyKey(type);

    final String title = (message.notification?.title ?? (data["title"] as String?) ?? "").trim();
    final String body = (message.notification?.body ?? (data["body"] as String?) ?? "").trim();

    String finalTitle = title.isNotEmpty ? title : NotificationCopy.title(key);
    String finalBody = body.isNotEmpty ? body : NotificationCopy.body(key);

    if (type == "chat_request") {
      if (finalTitle.trim().isEmpty || finalTitle == "New message") {
        finalTitle = "New chat request";
      }
      if (finalBody.trim().isEmpty) {
        finalBody = "Tap to accept or reply now.";
      }
    } else if (type == "party_message") {
      if (finalTitle.trim().isEmpty || finalTitle == "New message") {
        finalTitle = "Party member message";
      }
    }

    return NotificationItem(
      id: message.messageId ?? "push-${DateTime.now().millisecondsSinceEpoch}",
      type: type,
      title: finalTitle,
      body: finalBody,
      createdAtUtc: ts,
      seen: seen,
      data: data,
    );
  }

  Future<void> _showInAppBanner(NotificationItem item) async {
    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (BuildContext context) {
        return IgnorePointer(
          // Allow touches to pass through the overlay except on the banner itself.
          ignoring: true,
          child: SafeArea(
            top: true,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, left: 12, right: 12),
                child: IgnorePointer(
                  ignoring: false,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: InAppNotificationBanner(
                      title: item.title.isNotEmpty ? item.title : "Notification",
                      body: item.body,
                      type: item.type,
                      onTap: () {
                        // FIX: handleTap may be sync (void). Do not await.
                        NotificationRouter.instance.handleTap(context, item);
                      },
                      onDismiss: () {
                        try {
                          entry.remove();
                        } catch (_) {}
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
  }

  String _platform() {
    if (kIsWeb) return "web";
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return "android";
      case TargetPlatform.iOS:
        return "ios";
      case TargetPlatform.macOS:
        return "macos";
      case TargetPlatform.windows:
        return "windows";
      case TargetPlatform.linux:
        return "linux";
      case TargetPlatform.fuchsia:
        return "fuchsia";
    }
  }

  Future<void> notifyMatchCreated({
    required String matchId,
    required String aUid,
    required String bUid,
    required String creatorUid,
  }) async {
    if (kDebugMode) {
      debugPrint("[Push] notifyMatchCreated matchId=$matchId a=$aUid b=$bUid creator=$creatorUid");
    }
  }

  Future<void> notifyNewMessage({
    required String chatId,
    required String fromUid,
  }) async {
    if (kDebugMode) {
      debugPrint("[Push] notifyNewMessage chatId=$chatId from=$fromUid");
    }
  }

  Future<void> notifyMeetupEvent({
    required String chatId,
    required String creatorUid,
    required String otherUid,
    required String status,
  }) async {
    if (kDebugMode) {
      debugPrint("[Push] notifyMeetupEvent chatId=$chatId creator=$creatorUid other=$otherUid status=$status");
    }
  }

  Future<void> notifyBeaconEvent({
    required String meetupId,
    required String uid,
    required String mode,
    required String source,
  }) async {
    if (kDebugMode) {
      debugPrint("[Push] notifyBeaconEvent meetupId=$meetupId uid=$uid mode=$mode source=$source");
    }
  }

  Future<void> notifyNewChatMessage({
    required String chatId,
    required String fromUid,
  }) async {
    return notifyNewMessage(chatId: chatId, fromUid: fromUid);
  }

  Future<void> notifyMatch({
    required String matchId,
    required String aUid,
    required String bUid,
    required String creatorUid,
  }) async {
    return notifyMatchCreated(matchId: matchId, aUid: aUid, bUid: bUid, creatorUid: creatorUid);
  }

  Future<void> notifyMeetupUpdate({
    required String chatId,
    required String creatorUid,
    required String otherUid,
    required String status,
  }) async {
    return notifyMeetupEvent(chatId: chatId, creatorUid: creatorUid, otherUid: otherUid, status: status);
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _foregroundSub = null;
    _tokenRefreshSub = null;
    _initialized = false;
    _currentUid = null;
  }
}
