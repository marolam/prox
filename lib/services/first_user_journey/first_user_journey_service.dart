import "dart:async";
import "package:shared_preferences/shared_preferences.dart";

/// Account-scoped learning milestones; these never grant points or trust.
class FirstUserJourneyService {
  FirstUserJourneyService._();
  static final FirstUserJourneyService instance = FirstUserJourneyService._();

  void markInviteFriend(String uid) => _mark(uid, "invite");
  void markFirstChatSent(String uid) => _mark(uid, "chat");
  void markMeetupPlanned(String uid) => _mark(uid, "meetup");

  void _mark(String uid, String milestone) {
    if (uid.trim().isEmpty) return;
    unawaited(_save(uid, milestone).catchError((Object _) {}));
  }

  Future<void> _save(String uid, String milestone) async {
    final prefs = await SharedPreferences.getInstance();
    final key = "journey:$uid:$milestone";
    if (!prefs.containsKey(key)) await prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);
  }

  Future<Map<String, DateTime>> milestones(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final name in ["invite", "chat", "meetup"])
        if (prefs.getInt("journey:$uid:$name") case final int ms)
          name: DateTime.fromMillisecondsSinceEpoch(ms),
    };
  }
}
