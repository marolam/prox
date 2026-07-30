class ReciprocityService {
  ReciprocityService._();
  static final ReciprocityService instance = ReciprocityService._();

  void recordMeetupCompleted(String otherUid) {}
  void recordIncomingMessage(String otherUid) {}
  void recordThumbGiven(String otherUid) {}
}
