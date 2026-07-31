class ChatViewPresenceService {
  ChatViewPresenceService._();
  static final ChatViewPresenceService instance = ChatViewPresenceService._();

  final Set<String> _openChatIds = <String>{};

  void onChatOpened(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return;
    _openChatIds.add(id);
  }

  void onChatClosed(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return;
    _openChatIds.remove(id);
  }

  bool isChatOpen(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return false;
    return _openChatIds.contains(id);
  }
}
