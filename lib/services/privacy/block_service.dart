class BlockService {
  BlockService._();
  static final BlockService instance = BlockService._();

  final Set<String> _blocked = <String>{};

  Future<void> ensureLoaded() async {}

  bool isBlockedSync(String uid) {
    return _blocked.contains(uid.trim());
  }

  Future<void> block(String uid) async {
    final clean = uid.trim();
    if (clean.isNotEmpty) _blocked.add(clean);
  }
}
