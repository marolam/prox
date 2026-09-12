import "package:flutter/material.dart";
import "package:prox/screens/rating/rating_screen.dart";
import "package:prox/services/help/context_help_service.dart";

class PostMeetupFlow {
  const PostMeetupFlow._();
  static const instance = PostMeetupFlow._();

  static Future<void> run({
    required BuildContext context,
    required String chatId,
    required String otherUid,
    required int autoDefaultMs,
  }) async {
    final previous = ContextHelpService.instance.contextKey.value;
    ContextHelpService.instance.setContext("meetup:post_flow");
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RatingScreen(chatId: chatId, otherUid: otherUid),
        ),
      );
    } finally {
      ContextHelpService.instance.setContext(previous);
    }
  }
}
