import "package:cloud_firestore/cloud_firestore.dart";

import "package:prox/models/support_ticket.dart";

class SupportService {
  SupportService._();
  static final SupportService instance = SupportService._();

  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  Future<void> createTicket(SupportTicket ticket) async {
    final id = ticket.id.trim().isEmpty
        ? DateTime.now().millisecondsSinceEpoch.toString()
        : ticket.id.trim();

    await _fs.collection("supportTickets").doc(id).set(<String, dynamic>{
      "uid": ticket.uid,
      "subject": ticket.subject,
      "message": ticket.message,
      "status": ticket.status.name,
      "createdAt": Timestamp.fromDate(ticket.createdAt.toUtc()),
    }, SetOptions(merge: true));
  }
}
