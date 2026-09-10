import "package:flutter/material.dart";
import "package:prox/screens/matches/match_inbox_screen.dart";

/// Compatibility entry point; all discovery uses the maintained match inbox.
class MatchesScreen extends StatelessWidget {
  const MatchesScreen({super.key});
  @override
  Widget build(BuildContext context) => const MatchInboxScreen();
}
