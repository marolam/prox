class SupportTicketDraft {
  const SupportTicketDraft({
    required this.id,
    required this.subject,
    required this.message,
    required this.createdAt,
    this.context,
    this.updatedAt,
  });

  final String id;
  final String subject;
  final String message;
  final DateTime createdAt;
  final Object? context;
  final DateTime? updatedAt;

  SupportTicketDraft copyWith({
    String? id,
    String? subject,
    String? message,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SupportTicketDraft(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
