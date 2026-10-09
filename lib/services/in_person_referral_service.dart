import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:prox/services/location_privacy_service.dart';
import 'package:prox/services/app_check_headers.dart';

class InPersonReferralQr {
  const InPersonReferralQr({required this.link, required this.expiresAt});
  final String link;
  final DateTime expiresAt;
}

class InPersonReferralService {
  static Future<InPersonReferralQr> createQr({bool addToParty = true}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to invite someone.');
    final uid = user.uid;
    await LocationPrivacyService.instance.ensureLoaded();
    if (!LocationPrivacyService.instance.mayReadLocation ||
        !await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on location sharing to create an in-person QR.');
    }
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      throw StateError(
        'Allow location access before creating an in-person QR.',
      );
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
    if (!position.accuracy.isFinite || position.accuracy > 100) {
      throw StateError(
        'Location is too imprecise. Move outdoors and try again.',
      );
    }
    if (!LocationPrivacyService.instance.mayReadLocation ||
        FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('Your account or location settings changed. Try again.');
    }
    final idToken = await user.getIdToken();
    if (idToken == null) throw StateError('Sign in again to create an invite.');
    final response = await http
        .post(
          Uri.parse(
            'https://us-central1-prox-42bef.cloudfunctions.net/createReferralSingleUseToken',
          ),
          headers: {
            ...await appCheckHeaders(),
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'inPersonQrRequested': true,
            'partyConsent': addToParty,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'accuracyM': position.accuracy,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('Your signed-in account changed. Try again.');
    }
    if (response.statusCode != 200) {
      throw StateError('Could not create an in-person QR. Please try again.');
    }
    final result = jsonDecode(response.body) as Map<String, dynamic>;
    final token = result['token'] as String?;
    if (token == null || !RegExp(r'^T-[A-F0-9]{18}$').hasMatch(token)) {
      throw StateError('Could not create a valid in-person invite.');
    }
    // Use the verified app-link host so installed users can accept in Prox;
    // new users receive a landing page that preserves the token after install.
    final link = Uri.https('prox-us.com', '/', {
      't': token,
      if (addToParty) 'party': '1',
      'inperson': '1',
    }).toString();
    return InPersonReferralQr(
      link: link,
      expiresAt: DateTime.parse(result['expiresAt'] as String),
    );
  }
}
