import "package:cloud_firestore/cloud_firestore.dart";

class DashboardAnnouncement {
  const DashboardAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.active,
    required this.pinned,
    required this.broadcast,
    required this.audience,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String title;
  final String body;
  final bool active;
  final bool pinned;
  final bool broadcast;
  final String audience;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  bool get isExpired {
    final exp = expiresAt;
    if (exp == null) return false;
    return exp.isBefore(DateTime.now());
  }

  factory DashboardAnnouncement.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    DateTime? stamp(dynamic v) =>
        v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

    return DashboardAnnouncement(
      id: doc.id,
      title: (data["title"] ?? "").toString(),
      body: (data["body"] ?? "").toString(),
      active: data["active"] == true,
      pinned: data["pinned"] == true,
      broadcast: data["broadcast"] == true,
      audience: (data["audience"] ?? "all").toString(),
      createdAt: stamp(data["createdAt"]),
      expiresAt: stamp(data["expiresAt"]),
    );
  }
}
