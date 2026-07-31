import "dart:async";

import "package:flutter/foundation.dart";

import "package:firebase_core/firebase_core.dart";

import "package:firebase_auth/firebase_auth.dart";



import "../firebase_options.dart";



/// Centralized Firebase bootstrap with web-safe options + dev helpers.

class FirebaseBoot {

  static bool _ready = false;



  /// Ensure Firebase is initialized with platform options (web requires options).

  static Future<void> ensureInitialized() async {

    if (_ready) return;

    await Firebase.initializeApp(

      options: DefaultFirebaseOptions.currentPlatform,

    );

    debugPrint("[FirebaseBoot] Firebase initialized with options");

    _ready = true;

  }



  /// Legacy alias kept for older callers.

  static Future<void> init() => ensureInitialized();



  /// Dev-only: sign in anonymously if no current user.

  /// Useful for local web runs to bypass ProfileGate.

  static Future<void> devAutoSignIn() async {

    try {

      final auth = FirebaseAuth.instance;

      if (auth.currentUser == null) {

        await auth.signInAnonymously();

        debugPrint("[FirebaseBoot] Signed in anonymously for dev.");

      } else {

        debugPrint("[FirebaseBoot] Already signed in as ${auth.currentUser?.uid}");

      }

    } catch (e, st) {

      debugPrint("[FirebaseBoot] devAutoSignIn failed: $e\n$st");

    }

  }

}



/// Legacy top-level entry used by some probes.

Future<void> initFirebase() => FirebaseBoot.ensureInitialized();





