import "package:prox/models/presence_receipt.dart";

class PresenceReceiptService {
  PresenceReceiptService._();
  static final PresenceReceiptService instance = PresenceReceiptService._();

  final List<PresenceReceipt> _items = <PresenceReceipt>[];

  void add(PresenceReceipt receipt) {
    _items.add(receipt);
  }
}
