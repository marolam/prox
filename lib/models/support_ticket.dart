enum SupportTicketStatus { open, closed }

class SupportTicket {
  const SupportTicket({
    required this.id,
    String? uid,
    String? userId,
    this.technicianId = "",
    required this.subject,
    String? message,
    String? description,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
  })  : uid = uid ?? userId ?? "",
        message = message ?? description ?? "";

  final String id;
  final String uid;
  final String technicianId;
  final String subject;
  final String message;
  final SupportTicketStatus status;
  final DateTime createdAt;
  final DateTime? resolvedAt;
}
