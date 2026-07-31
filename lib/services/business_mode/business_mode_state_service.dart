import "package:cloud_firestore/cloud_firestore.dart";
import "package:prox/services/device_storage_service.dart";

class BusinessModeStateService {
  BusinessModeStateService._();
  static final BusinessModeStateService instance = BusinessModeStateService._();

  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  static const String _testerUnlocksKey = "businessMode.testerUnlocks";

  DocumentReference<Map<String, dynamic>> _entitlementRef(String uid) {
    return _fs
        .collection("users")
        .doc(uid)
        .collection("billing")
        .doc("entitlements");
  }

  Future<bool> isActive(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return false;
    final snap = await _entitlementRef(u).get();
    return snap.data()?['businessModeActive'] == true;
  }

  Future<void> setActive(String uid, bool active) async {
    final u = uid.trim();
    if (u.isEmpty) return;
    await _entitlementRef(u).set(
      <String, Object?>{
        'businessModeActive': active,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<bool> isTesterUnlocked(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return false;
    await DeviceStorageService.instance.load();
    final raw = DeviceStorageService.instance.getMap(_testerUnlocksKey);
    return raw?[u] == true;
  }

  Future<void> setTesterUnlocked(String uid, bool unlocked) async {
    final u = uid.trim();
    if (u.isEmpty) return;
    await DeviceStorageService.instance.updateMapEntry(
      key: _testerUnlocksKey,
      entryKey: u,
      value: unlocked ? true : null,
    );
  }
}
