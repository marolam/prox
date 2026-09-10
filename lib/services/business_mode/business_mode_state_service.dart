import "package:prox/services/business_mode/business_access_policy.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import "package:cloud_functions/cloud_functions.dart";
import "package:firebase_auth/firebase_auth.dart";

/// Only confirmed server state can activate the paid business tools.
class BusinessModeStateService {
  BusinessModeStateService._();
  static final BusinessModeStateService instance = BusinessModeStateService._();

  String _requireOwner(String uid) {
    final clean = uid.trim();
    if (clean.isEmpty || FirebaseAuth.instance.currentUser?.uid != clean) {
      throw StateError("Sign in to manage your Pro Mode settings.");
    }
    return clean;
  }

  Future<bool> isActive(String uid) async {
    final clean = _requireOwner(uid);
    final snap = await FirebaseFirestore.instance
        .doc("users/$clean/billing/entitlements")
        .get()
        .timeout(const Duration(seconds: 8));
    if (FirebaseAuth.instance.currentUser?.uid != clean) return false;
    final data = snap.data() ?? <String, dynamic>{};
    return data["businessModeActive"] == true &&
        BusinessAccessPolicy.hasAccess(data);
  }

  Future<void> setActive(String uid, bool active) async {
    final clean = _requireOwner(uid);
    final result = await FirebaseFunctions.instanceFor(region: "us-central1")
        .httpsCallable(
          "setBusinessModeActive",
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call(<String, Object?>{"active": active});
    if (FirebaseAuth.instance.currentUser?.uid != clean) {
      throw StateError("Your account changed. Reopen Pro Mode.");
    }
    if (result.data is! Map || result.data["active"] != active) {
      throw StateError("Pro Mode activation was not confirmed. Try again.");
    }
  }
}
