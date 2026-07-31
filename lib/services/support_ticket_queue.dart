import "dart:async";

import "package:flutter/foundation.dart";
import "package:prox/models/support_ticket_draft.dart";

class SupportTicketQueue extends ChangeNotifier {
  SupportTicketQueue._();
  static final SupportTicketQueue instance = SupportTicketQueue._();

  final Map<String, SupportTicketDraft> _drafts = <String, SupportTicketDraft>{};
  final StreamController<List<SupportTicketDraft>> _controller =
      StreamController<List<SupportTicketDraft>>.broadcast();

  Stream<List<SupportTicketDraft>> watchDrafts() => _controller.stream;

  List<SupportTicketDraft> get drafts {
    final items = _drafts.values.toList(growable: false)
      ..sort((a, b) => (b.updatedAt ?? b.createdAt).compareTo(a.updatedAt ?? a.createdAt));
    return items;
  }

  void upsertDraft(SupportTicketDraft draft) {
    _drafts[draft.id] = draft.copyWith(updatedAt: DateTime.now());
    _emit();
  }

  void removeDraft(String draftId) {
    _drafts.remove(draftId);
    _emit();
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(drafts);
    }
    notifyListeners();
  }
}
