import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

class PartyProfileSharing {
  final String about;
  final String contactEmail;
  final String phone;
  final String generalArea;
  final bool shareAbout;
  final bool shareContactEmail;
  final bool sharePhone;
  final bool shareGeneralArea;
  final bool shareHeadline;
  final bool shareKeywords;

  const PartyProfileSharing({
    this.about = "",
    this.contactEmail = "",
    this.phone = "",
    this.generalArea = "",
    this.shareAbout = false,
    this.shareContactEmail = false,
    this.sharePhone = false,
    this.shareGeneralArea = false,
    this.shareHeadline = false,
    this.shareKeywords = false,
  });

  factory PartyProfileSharing.fromMap(Map<String, dynamic> data) {
    String textValue(String key) => (data[key] ?? "").toString().trim();
    return PartyProfileSharing(
      about: textValue("about"),
      contactEmail: textValue("contactEmail"),
      phone: textValue("phone"),
      generalArea: textValue("generalArea"),
      shareAbout: data["shareAbout"] == true,
      shareContactEmail: data["shareContactEmail"] == true,
      sharePhone: data["sharePhone"] == true,
      shareGeneralArea: data["shareGeneralArea"] == true,
      shareHeadline: data["shareHeadline"] == true,
      shareKeywords: data["shareKeywords"] == true,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        "about": about.trim(),
        "contactEmail": contactEmail.trim(),
        "phone": phone.trim(),
        "generalArea": generalArea.trim(),
        "shareAbout": shareAbout && about.trim().isNotEmpty,
        "shareContactEmail":
            shareContactEmail && contactEmail.trim().isNotEmpty,
        "sharePhone": sharePhone && phone.trim().isNotEmpty,
        "shareGeneralArea": shareGeneralArea && generalArea.trim().isNotEmpty,
        "shareHeadline": shareHeadline,
        "shareKeywords": shareKeywords,
      };

  bool get sharesAnyCustomField =>
      (shareAbout && about.isNotEmpty) ||
      (shareContactEmail && contactEmail.isNotEmpty) ||
      (sharePhone && phone.isNotEmpty) ||
      (shareGeneralArea && generalArea.isNotEmpty);
}

class PartyProfileService {
  PartyProfileService._();
  static final PartyProfileService instance = PartyProfileService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  DocumentReference<Map<String, dynamic>> _sharingDoc(String uid) => _db
      .collection("users")
      .doc(uid)
      .collection("partyProfile")
      .doc("sharing");

  String _me() {
    final uid = _auth.currentUser?.uid.trim() ?? "";
    if (uid.isEmpty) throw StateError("Sign in required.");
    return uid;
  }

  Future<PartyProfileSharing> loadMine() async {
    final snap = await _sharingDoc(_me()).get();
    return PartyProfileSharing.fromMap(
      snap.data() ?? const <String, dynamic>{},
    );
  }

  Future<void> saveMine(PartyProfileSharing sharing) async {
    await _sharingDoc(_me()).set(<String, Object?>{
      ...sharing.toMap(),
      "updatedAt": FieldValue.serverTimestamp(),
    });
  }

  Stream<PartyProfileSharing> watchMember(String uid) => _sharingDoc(uid.trim())
      .snapshots()
      .map((snap) => PartyProfileSharing.fromMap(
            snap.data() ?? const <String, dynamic>{},
          ));
}
