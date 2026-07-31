import "package:flutter/material.dart";

class ReferralDemoWalkthroughScreen extends StatefulWidget {
  const ReferralDemoWalkthroughScreen({super.key});

  @override
  State<ReferralDemoWalkthroughScreen> createState() =>
      _ReferralDemoWalkthroughScreenState();
}

class _ReferralDemoWalkthroughScreenState
    extends State<ReferralDemoWalkthroughScreen> {
  final PageController _controller = PageController();
  int _index = 0;
  bool _completed = false;

  static const List<_DemoStep> _steps = <_DemoStep>[
    _DemoStep(
      title: "What Prox is for",
      subtitle:
          "Prox helps nearby people turn shared intent into a safe chat, a planned meetup, and a trusted Party connection.",
      screenTitle: "Prox path",
      screenSubtitle: "Profile to real-world connection",
      icon: Icons.hub_outlined,
      rows: <_DemoLine>[
        _DemoLine(Icons.person_outline, "Profile", "Tell Prox who you are"),
        _DemoLine(
            Icons.radar_outlined, "Nearby", "Find relevant people around you"),
        _DemoLine(
            Icons.chat_bubble_outline, "Chat", "Request and confirm interest"),
        _DemoLine(Icons.place_outlined, "Meetup", "Pick a clear in-app plan"),
        _DemoLine(Icons.group_outlined, "Party", "Keep trusted people close"),
      ],
      callouts: <String>[
        "Prox is strongest when your profile says what you want and what you can offer.",
        "Nearby is not just a list of strangers. It uses intent, trust, distance, and activity signals.",
        "The full loop is profile, nearby match, chat, meetup, then Party or referral follow-up.",
      ],
      tips: <String>[
        "Think in outcomes: help finding a workout partner, local service lead, event buddy, collaborator, or support contact.",
        "Use specific keywords. 'Tennis doubles' beats 'sports'. 'Need logo help' beats 'business'.",
      ],
    ),
    _DemoStep(
      bigFiveLabel: "Big 5: 1 of 5",
      title: "Profile setup",
      subtitle:
          "Your profile is the source material for matches. A clear photo and concrete keywords help Prox understand intent.",
      screenTitle: "Create profile",
      screenSubtitle: "The screen users see after sign-in",
      icon: Icons.badge_outlined,
      rows: <_DemoLine>[
        _DemoLine(
            Icons.account_circle_outlined, "Selfie", "Required for trust"),
        _DemoLine(Icons.search_outlined, "Searching For", "What you want now"),
        _DemoLine(
            Icons.handshake_outlined, "Can Provide", "What you can help with"),
        _DemoLine(Icons.save_outlined, "Save", "Unlock matching"),
      ],
      callouts: <String>[
        "Selfie: use a clear recent photo so chat and meetup steps feel safer.",
        "Searching For: add the exact thing you want to accomplish, not a broad category.",
        "Can Provide: describe useful help, skill, availability, or local knowledge you can offer.",
      ],
      tips: <String>[
        "Pair opposite intents when possible: 'need car detail' and 'offer web design' gives Prox more ways to connect you.",
        "Update your keywords before each session if today's goal is different from last time.",
      ],
    ),
    _DemoStep(
      bigFiveLabel: "Big 5: 2 of 5",
      title: "Nearby and Prox Circle",
      subtitle:
          "Nearby is where Prox shows people who fit your current intent, distance, mode, and trust context.",
      screenTitle: "Nearby",
      screenSubtitle: "Match cards and Prox Circle",
      icon: Icons.explore_outlined,
      rows: <_DemoLine>[
        _DemoLine(
            Icons.blur_on, "Prox Circle", "Privacy-safe direction signal"),
        _DemoLine(Icons.tune_outlined, "Radius", "Wider is not always better"),
        _DemoLine(Icons.local_fire_department_outlined, "Active",
            "Use when ready now"),
        _DemoLine(Icons.person_search_outlined, "Match card",
            "Intent and trust clues"),
      ],
      callouts: <String>[
        "Prox Circle hints at general direction and signal strength without exposing exact locations.",
        "Match cards show why someone appears, such as shared keywords, referral warmth, or activity.",
        "Active mode is for immediate follow-through. Passive mode is better when you are browsing.",
      ],
      tips: <String>[
        "Start with a tighter radius when your goal depends on meeting soon.",
        "If results feel noisy, make Searching For more specific before widening distance.",
        "If results feel empty, broaden one keyword at a time instead of changing everything at once.",
      ],
    ),
    _DemoStep(
      bigFiveLabel: "Big 5: 3 of 5",
      title: "Chat request",
      subtitle:
          "A chat request confirms mutual intent before the conversation opens. The first message should make the next step easy.",
      screenTitle: "Chat request",
      screenSubtitle: "Request, accept, then message",
      icon: Icons.mark_chat_unread_outlined,
      rows: <_DemoLine>[
        _DemoLine(Icons.outgoing_mail, "Request", "Ask to start chat"),
        _DemoLine(Icons.check_circle_outline, "Accept", "Recipient confirms"),
        _DemoLine(Icons.message_outlined, "Message", "State goal and timing"),
        _DemoLine(Icons.security_outlined, "Safety",
            "Use block or leave when needed"),
      ],
      callouts: <String>[
        "Request Chat tells the other person why you want to connect before a thread becomes active.",
        "Accept Chat Request appears for the recipient when a valid request is waiting.",
        "The chat screen is where meetup actions appear after both sides show enough intent.",
      ],
      tips: <String>[
        "Lead with the goal: 'I saw you can help with resumes. Are you free for a 10 minute chat today?'",
        "Add a time window and one useful detail so the other person can answer quickly.",
        "If the match is not right, leave the chat cleanly rather than forcing the flow.",
      ],
    ),
    _DemoStep(
      bigFiveLabel: "Big 5: 4 of 5",
      title: "Meetup planning",
      subtitle:
          "Meetup planning turns chat intent into a clear place, status, and completion path inside the app.",
      screenTitle: "Meetup planner",
      screenSubtitle: "Pick, confirm, navigate, complete",
      icon: Icons.map_outlined,
      rows: <_DemoLine>[
        _DemoLine(Icons.location_on_outlined, "Location",
            "Use midpoint, current, or pin"),
        _DemoLine(
            Icons.compare_arrows_outlined, "Proposal", "Both users confirm"),
        _DemoLine(
            Icons.directions_walk_outlined, "On my way", "Live progress state"),
        _DemoLine(Icons.flag_outlined, "Arrived", "Complete the meetup"),
      ],
      callouts: <String>[
        "The planner helps both people agree on the same place instead of juggling outside maps.",
        "Live meetup status keeps the session focused until it ends.",
        "After arrival, completion and rating protect the quality of future matches.",
      ],
      tips: <String>[
        "Suggest public, easy-to-find locations when meeting someone new.",
        "Use in-app navigation states so the other person knows whether you are still coming.",
        "If plans change, update the meetup instead of opening a second thread or stale plan.",
      ],
    ),
    _DemoStep(
      bigFiveLabel: "Big 5: 5 of 5",
      title: "After the meetup",
      subtitle:
          "The final step improves future matching: rate the meetup, add trusted people to Party, and use referrals intentionally.",
      screenTitle: "After meetup",
      screenSubtitle: "Rating, Party, referrals, points",
      icon: Icons.verified_outlined,
      rows: <_DemoLine>[
        _DemoLine(Icons.thumb_up_alt_outlined, "Rate", "Confirm quality"),
        _DemoLine(
            Icons.group_add_outlined, "Add to Party", "Keep trusted matches"),
        _DemoLine(
            Icons.qr_code_2_outlined, "Referral", "Invite people you trust"),
        _DemoLine(
            Icons.stars_outlined, "Points", "Progress from real activity"),
      ],
      callouts: <String>[
        "Positive meetups can become Party connections, which makes future discovery warmer and safer.",
        "Referrals help trusted people join with context instead of starting cold.",
        "Points and progress are tied to meaningful activity, not random tapping.",
      ],
      tips: <String>[
        "Only add people to Party when you would be comfortable seeing them again or vouching for the connection.",
        "Invite people whose goals fit the app. A good referral improves the network for everyone nearby.",
      ],
    ),
    _DemoStep(
      title: "Getting better results",
      subtitle:
          "Use Prox like a goal loop: set intent, test nearby, adjust one detail, then try again.",
      screenTitle: "Result tuning",
      screenSubtitle: "How to customize the next session",
      icon: Icons.auto_fix_high_outlined,
      rows: <_DemoLine>[
        _DemoLine(Icons.edit_note_outlined, "Keywords", "Change one at a time"),
        _DemoLine(Icons.social_distance_outlined, "Radius",
            "Match the real-world goal"),
        _DemoLine(Icons.schedule_outlined, "Timing", "Active when ready"),
        _DemoLine(
            Icons.support_agent_outlined, "Support", "Ask for help when stuck"),
      ],
      callouts: <String>[
        "For business or services, name the customer intent, not only the service name.",
        "For social goals, include the actual activity, location style, or availability window.",
        "For help requests, say what a useful next step looks like so the match can respond clearly.",
      ],
      tips: <String>[
        "Examples: 'need pickleball partner today', 'offer mobile mechanic advice', 'looking for event photographer', 'can review resumes'.",
        "If you get stuck after creating a profile, go to Nearby first, then Chat, then Meetup. Referrals and Party improve the next pass.",
        "Complete this walkthrough once, then use it as a mental map while exploring the app.",
      ],
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    final last = _index >= _steps.length - 1;
    if (last) {
      setState(() => _completed = true);
      Navigator.of(context).pop(true);
      return;
    }

    await _controller.nextPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final progress = (_index + 1) / _steps.length;
    final last = _index >= _steps.length - 1;

    return PopScope(
      canPop: _completed,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text("Prox Demo"),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Step ${_index + 1} of ${_steps.length}",
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          "No skipping",
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: progress),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _steps.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, index) =>
                      _DemoStepPage(step: _steps[index]),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(
                      top: BorderSide(
                          color: cs.outline.withValues(alpha: 0.18))),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _next,
                    icon: Icon(last ? Icons.check : Icons.arrow_forward),
                    label: Text(last ? "Finish demo" : "Next"),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoStepPage extends StatelessWidget {
  const _DemoStepPage({required this.step});

  final _DemoStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        if (step.bigFiveLabel != null) ...[
          Text(
            step.bigFiveLabel!,
            style: theme.textTheme.labelLarge?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          step.title,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          step.subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 16),
        _PhoneExample(step: step),
        const SizedBox(height: 16),
        _InfoBlock(
          title: "What this screen means",
          icon: Icons.info_outline,
          items: step.callouts,
        ),
        const SizedBox(height: 12),
        _InfoBlock(
          title: "How to get better results",
          icon: Icons.lightbulb_outline,
          items: step.tips,
        ),
      ],
    );
  }
}

class _PhoneExample extends StatelessWidget {
  const _PhoneExample({required this.step});

  final _DemoStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outline.withValues(alpha: 0.26)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(step.icon, color: cs.onPrimaryContainer),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.screenTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            step.screenSubtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: cs.outline.withValues(alpha: 0.18)),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final row in step.rows) ...[
                      _DemoScreenRow(row: row),
                      if (row != step.rows.last) const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoScreenRow extends StatelessWidget {
  const _DemoScreenRow({required this.row});

  final _DemoLine row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(row.icon, size: 20, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  row.value,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in items) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    item,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.25),
                  ),
                ),
              ],
            ),
            if (item != items.last) const SizedBox(height: 7),
          ],
        ],
      ),
    );
  }
}

class _DemoStep {
  const _DemoStep({
    this.bigFiveLabel,
    required this.title,
    required this.subtitle,
    required this.screenTitle,
    required this.screenSubtitle,
    required this.icon,
    required this.rows,
    required this.callouts,
    required this.tips,
  });

  final String? bigFiveLabel;
  final String title;
  final String subtitle;
  final String screenTitle;
  final String screenSubtitle;
  final IconData icon;
  final List<_DemoLine> rows;
  final List<String> callouts;
  final List<String> tips;
}

class _DemoLine {
  const _DemoLine(this.icon, this.title, this.value);

  final IconData icon;
  final String title;
  final String value;
}
