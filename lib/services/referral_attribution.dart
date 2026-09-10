import "package:prox/services/location_privacy_service.dart";
import "dart:async";
import "dart:convert";

import 'package:cloud_functions/cloud_functions.dart';
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";
import "package:geolocator/geolocator.dart";
import "package:http/http.dart" as http;

import "package:prox/services/device_storage_service.dart";

class ReferralAttribution {
  ReferralAttribution._();
  static final ReferralAttribution instance = ReferralAttribution._();

  static const String _kStorageKey = "pending_referral_signal_v1";
  static const String _kFinalizeTokenUrl =
      "https://us-central1-prox-42bef.cloudfunctions.net/finalizeReferralSingleUseToken";
  static const String _kReferralServerHost = "prox-us.com";
  static const String _kReferralHost = "prox.page.link";

  Future<void> captureFromLaunchUri(Uri uri) async {
    final payload = _extractReferralPayload(uri);
    if (payload == null) return;
    await DeviceStorageService.instance.set(_kStorageKey, payload);
  }

  Future<bool> applyIfPossible({
    String explicitUid = "",
    String uid = "",
  }) async {
    final targetUid = explicitUid.trim().isNotEmpty
        ? explicitUid.trim()
        : uid.trim();

    if (targetUid.isEmpty) {
      return false;
    }

    await DeviceStorageService.instance.load();
    if (FirebaseAuth.instance.currentUser?.uid != targetUid) return false;
    final raw = DeviceStorageService.instance.getMap(_kStorageKey);
    if (raw == null || raw.isEmpty) return false;

    final bool alreadyApplied = (raw["applied"] as bool?) == true;
    if (alreadyApplied) {
      await DeviceStorageService.instance.set(_kStorageKey, raw);
      return false;
    }

    final String? token = _normalizeString(raw["token"]?.toString());
    final String? code = _normalizeString(raw["code"]?.toString());
    final String? referrerUid = _normalizeString(raw["ref"]);
    final bool isInPerson = raw["inperson"] == true || raw["party"] == true;
    final int receivedMs = raw["receivedAtMs"] is int
        ? (raw["receivedAtMs"] as int)
        : 0;

    // Hard-stop stale payloads to prevent stale account-linking a year later.
    if (receivedMs > 0 &&
        DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(receivedMs),
            ) >
            const Duration(hours: 72)) {
      await _clearPendingReferral();
      return false;
    }

    if (token != null && token.isNotEmpty) {
      final bool ok = await _finalizeSingleUseToken(
        uid: targetUid,
        token: token,
        allowPersonVerified: isInPerson,
      );
      if (ok) {
        await _clearPendingReferral();
        return true;
      }
      return false;
    }

    if (referrerUid == null ||
        referrerUid.isEmpty ||
        code == null ||
        code.isEmpty) {
      await _clearPendingReferral();
      return false;
    }

    final bool ok = await _applyCodeReferral(
      uid: targetUid,
      code: code,
      referrerUid: referrerUid,
      inPersonRequested: isInPerson,
    );
    if (ok) {
      await _clearPendingReferral();
      return true;
    }

    return false;
  }

  Future<void> markProfileComplete({required String uid}) async {
    if (uid.isEmpty) return;
    await DeviceStorageService.instance.set("profile_completed:$uid", true);
  }

  Future<void> verifyFromMeetupCompletion({
    required String meetupId,
    required String aUid,
    required String bUid,
  }) async {
    if (meetupId.trim().isEmpty) return;
    if (aUid.trim().isEmpty || bUid.trim().isEmpty) return;
    await FirebaseFunctions.instance
        .httpsCallable('syncCompletedMeetup')
        .call<void>({'meetupId': meetupId});
  }

  Future<bool> _applyCodeReferral({
    required String uid,
    required String code,
    required String referrerUid,
    required bool inPersonRequested,
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) return false;
    final result = await FirebaseFunctions.instance
        .httpsCallable('linkReferralCode')
        .call<Map<String, dynamic>>({'code': code});
    return result.data['linked'] == true;
  }

  Future<bool> _finalizeSingleUseToken({
    required String uid,
    required String token,
    required bool allowPersonVerified,
  }) async {
    try {
      if (token.trim().isEmpty) return false;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid.trim() != uid.trim()) return false;

      final String? idToken = await user.getIdToken(true);
      if (idToken == null || idToken.isEmpty) return false;

      final Position? pos = await _readPosition();
      final Map<String, dynamic> body = <String, dynamic>{"token": token};
      if (pos != null) {
        body["latitude"] = pos.latitude;
        body["longitude"] = pos.longitude;
        body["accuracyM"] = pos.accuracy.isFinite ? pos.accuracy : 100;
      }

      final http.Response res = await http
          .post(
            Uri.parse(_kFinalizeTokenUrl),
            headers: <String, String>{
              "Authorization": "Bearer $idToken",
              "Content-Type": "application/json",
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));

      final Map<String, dynamic> payload = _parseJsonMap(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (kDebugMode) {
          final String? ref = payload["referrerUid"]?.toString();
          debugPrint(
            "[ReferralAttribution] finalize token succeeded for token=$token ref=$ref",
          );
        }
        return true;
      }

      final String reason = payload["error"]?.toString() ?? "unknown";
      if (kDebugMode) {
        debugPrint(
          "[ReferralAttribution] finalize token failed ($reason) status=${res.statusCode} token=$token",
        );
      }

      if (res.statusCode == 404 ||
          res.statusCode == 409 ||
          res.statusCode == 403 ||
          res.statusCode == 401 ||
          res.statusCode == 410) {
        return false;
      }

      // Keep transient payload for retry on server-side outage.
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint("[ReferralAttribution] finalize token error: $e");
      }
      return false;
    }
  }

  Future<Position?> _readPosition() async {
    await LocationPrivacyService.instance.ensureLoaded();
    if (!LocationPrivacyService.instance.mayReadLocation) return null;
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;

      final LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 3),
        ),
      );
      return LocationPrivacyService.instance.mayReadLocation ? position : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearPendingReferral() async {
    try {
      await DeviceStorageService.instance.set(
        _kStorageKey,
        <String, dynamic>{},
      );
    } catch (_) {}
  }

  Map<String, dynamic>? _extractReferralPayload(Uri? uri) {
    if (uri == null) return null;

    final Uri? wrapped = _unwrapDeepLink(uri);
    final Uri effective = wrapped ?? uri;

    if (!isTrustedReferralUri(uri) || !isTrustedReferralUri(effective))
      return null;

    final Map<String, String> raw = effective.queryParameters;

    final String? rawToken = _normalizeString(
      raw["t"] ?? raw["token"] ?? raw["tok"] ?? raw["referral_token"],
    );
    final String? rawCode = _normalizeString(
      raw["code"] ?? raw["ref"] ?? raw["referral"] ?? raw["invite"],
    );
    final String? ref = _normalizeString(
      raw["ref"] ?? raw["referrer"] ?? raw["r"],
    );
    final String? codeFromRef = _normalizeString(raw["code"]);
    final String? refFromCode = _normalizeString(raw["ref"]);

    final bool party =
        _parseBool(raw["party"]) ||
        _parseBool(raw["inperson"]) ||
        _parseBool(raw["in_person"]) ||
        _parseBool(raw["ip"]);

    final String? chosenRef = ref ?? refFromCode;
    final String? chosenCode = rawCode ?? codeFromRef;

    if ((chosenRef == null || chosenRef.isEmpty) &&
        (rawToken == null || rawToken.isEmpty)) {
      return null;
    }

    if (rawToken != null && rawToken.isNotEmpty && chosenRef == null) {
      return null;
    }

    if (chosenCode == null || chosenCode.isEmpty) {
      if (rawToken == null || rawToken.isEmpty) return null;
    }

    return <String, dynamic>{
      "token": rawToken,
      "ref": chosenRef,
      "code": chosenCode,
      "party": party,
      "inperson": party,
      "receivedAtMs": DateTime.now().millisecondsSinceEpoch,
      "applied": false,
    };
  }

  Uri? _unwrapDeepLink(Uri uri) {
    if (uri.host == _kReferralHost || uri.host == "www.${_kReferralHost}") {
      final String link = _normalizeString(uri.queryParameters["link"]) ?? "";
      if (link.isNotEmpty) {
        try {
          return Uri.parse(link);
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  static bool isTrustedReferralUri(Uri uri) {
    if (uri.userInfo.isNotEmpty || uri.hasPort) return false;
    final host = uri.host.toLowerCase();
    if (uri.scheme == "prox")
      return const {"referral", "ref", "invite"}.contains(host);
    return uri.scheme == "https" &&
        const {
          _kReferralServerHost,
          "www.prox-us.com",
          _kReferralHost,
          "www.prox.page.link",
        }.contains(host);
  }

  String? _normalizeString(String? v) {
    if (v == null) return null;
    final String t = v.trim();
    return t.isEmpty ? null : t;
  }

  bool _parseBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    final String s = v.toString().trim().toLowerCase();
    return s == "1" || s == "true" || s == "yes" || s == "y" || s == "on";
  }

  Map<String, dynamic> _parseJsonMap(String raw) {
    if (raw.isEmpty) return <String, dynamic>{};
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {}
    return <String, dynamic>{};
  }
}
