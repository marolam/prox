class PresenceReceipt {
  const PresenceReceipt({
    required this.ts,
    required this.otherUid,
    required this.label,
    required this.onTime,
  });

  final DateTime ts;
  final String otherUid;
  final String label;
  final bool onTime;
}
