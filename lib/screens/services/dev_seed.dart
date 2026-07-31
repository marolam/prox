import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";

/// Developer seeding helpers. Now with strictly typed exception handling.
class DevSeedService {
  DevSeedService(this._db, this._auth);
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  Future<void> ensureDemoProfile(String uid) async {
    try {
      final ref = _db.collection("profiles").doc(uid);
      await ref.set(<String, Object?>{
        "name": "Demo User",
        "createdAt": FieldValue.serverTimestamp(),
        "trustScore": 50.0,
      }, SetOptions(merge: true));
    } on FirebaseException catch (e, st) {
      _logFirebase("ensureDemoProfile", e, st);
      rethrow;
    } catch (e, st) {
      _log("UNKNOWN ensureDemoProfile: $e", st);
      rethrow;
    }
  }

  /// Simple sign-in shim for web/desktop/mobile; no JS interop here.
  Future<UserCredential?> signInAnonymously() async {
    try {
      final cred = await _auth.signInAnonymously();
      return cred;
    } on FirebaseAuthException catch (e, st) {
      _log("AUTH signInAnonymously failed: code=${e.code}, message=${e.message ?? ""}", st);
      return null;
    } on FirebaseException catch (e, st) {
      _logFirebase("signInAnonymously", e, st);
      return null;
    } catch (e, st) {
      _log("UNKNOWN signInAnonymously: $e", st);
      return null;
    }
  }

  void _logFirebase(String op, FirebaseException e, StackTrace st) {
    if (kDebugMode) {
      // ignore: avoid_print
      print("[DevSeed] FIREBASE $op: code=${e.code}, message=${e.message ?? ""}");
      // ignore: avoid_print
      print(st);
    }
  }

  void _log(String msg, [StackTrace? st]) {
    if (kDebugMode) {
      // ignore: avoid_print
      print("[DevSeed] $msg");
      if (st != null) {
        // ignore: avoid_print
        print(st);
      }
    }
  }
}

