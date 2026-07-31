import "package:cloud_firestore/cloud_firestore.dart";

class TrustedBusinessContactsService {
  TrustedBusinessContactsService._();
  static final TrustedBusinessContactsService instance =
      TrustedBusinessContactsService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _contactRef({
    required String ownerUid,
    required String contactUid,
  }) {
    return _db
        .collection("users")
        .doc(ownerUid)
        .collection("trustedBusinessContacts")
        .doc(contactUid);
  }

  Future<bool> isTrustedContact({
    required String ownerUid,
    required String contactUid,
  }) async {
    final owner = ownerUid.trim();
    final contact = contactUid.trim();
    if (owner.isEmpty || contact.isEmpty) return false;

    final snap = await _contactRef(ownerUid: owner, contactUid: contact).get();
    return snap.exists;
  }

  Future<void> addTrustedContact({
    required String ownerUid,
    required String contactUid,
    required String sourceChatId,
  }) async {
    final owner = ownerUid.trim();
    final contact = contactUid.trim();
    final chatId = sourceChatId.trim();
    if (owner.isEmpty || contact.isEmpty) return;

    await _contactRef(ownerUid: owner, contactUid: contact).set(
      <String, Object?>{
        "ownerUid": owner,
        "contactUid": contact,
        "sourceChatId": chatId,
        "addedAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
