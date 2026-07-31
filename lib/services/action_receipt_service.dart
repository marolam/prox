import "dart:async";

class ActionReceipt {
  const ActionReceipt({
    required this.kind,
    required this.title,
    required this.detail,
    required this.createdAt,
  });

  final String kind;
  final String title;
  final String detail;
  final DateTime createdAt;
}

class ActionReceiptService {
  ActionReceiptService._();
  static final ActionReceiptService instance = ActionReceiptService._();

  final StreamController<List<ActionReceipt>> _controller =
      StreamController<List<ActionReceipt>>.broadcast();
  final List<ActionReceipt> _items = <ActionReceipt>[];

  Stream<List<ActionReceipt>> watch() => _controller.stream;

  Future<void> add({
    required String kind,
    required String title,
    required String detail,
  }) async {
    _items.insert(
      0,
      ActionReceipt(
        kind: kind,
        title: title,
        detail: detail,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    if (!_controller.isClosed) {
      _controller.add(List<ActionReceipt>.unmodifiable(_items));
    }
  }
}
