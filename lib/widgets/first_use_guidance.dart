import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:prox/screens/referral/referral_demo_walkthrough_screen.dart';
import 'package:prox/services/first_use_service.dart';
import 'package:prox/services/simple_mode/simple_mode_policy.dart';

const firstUseWelcome =
    'Prox helps you turn nearby people into useful connections. Find a workout '
    'partner, help with a project, a local service, or people who share your '
    'interests.\n\nTell Prox what you are looking for and what you can offer. '
    'Discover relevant people nearby, connect by mutual agreement, and plan '
    'a meetup in a public place.\n\nYou are helping build your local Prox '
    'community. More people participating nearby can mean more opportunities. '
    'Invite people who could benefit using your in-person QR. Invitations '
    'are optional: there is no recruiting quota to finish this guide.\n\n'
    'New accounts need in-person verification for full access. If someone '
    'invited you, stay together and reopen their QR after installing.';

typedef FirstUseStop = ({String tab, String title, String detail});
const firstUseStops = <FirstUseStop>[
  (
    tab: 'Profile',
    title: 'Make your profile useful',
    detail:
        'Start with your name and a clear, recent selfie. Looking For '
        '(also called Searching For) describes what you need; Can Provide '
        'describes what you offer. "Tennis doubles" or "resume review" works '
        'better than "sports" or "business". Save your changes in Profile.',
  ),
  (
    tab: 'Nearby',
    title: 'Explore Nearby and the Prox Circle',
    detail:
        'Nearby opens discovery. The Prox Circle gives '
        'a general direction signal, not someone\'s exact location. Use Radius '
        'and Mode to review discovery settings. Active means ready to connect '
        'now; Passive is for remaining available. This tour never changes your '
        'mode or sends a request. Empty results can simply mean your local '
        'community is still growing.',
  ),
  (
    tab: 'Meetups',
    title: 'Connect by agreement, then meet safely',
    detail:
        'Review a current match and use the available request actions. '
        'The other person must agree before the conversation or meetup moves '
        'forward. Chat about your goal, agree on a public meeting place, and '
        'follow the meetup status through completion and feedback. The demo '
        'below uses examples only: it never contacts a real person.',
  ),
  (
    tab: 'Party',
    title: 'Keep trusted connections in your Party',
    detail:
        'Party is your network of people you have connected with in person. '
        'Use the in-person flow and respect both people\'s consent. Inviting '
        'someone to install Prox does not automatically make them a trusted '
        'Party member. You can decline contact, block, or report concerns.',
  ),
  (
    tab: 'Referrals',
    title: 'Help your local community grow',
    detail:
        'Swipe the bottom navigation for Referrals. When you meet someone '
        'who could benefit, open Referrals and choose Create in-person QR. '
        'Stay together while they install, then reopen or refresh the QR link '
        'to finish in-person verification. Location, expiry, consent, and '
        'account eligibility still apply. A screenshot or forwarded link is '
        'not a substitute. Inviting is optional, not a recruiting requirement.',
  ),
  (
    tab: 'Settings',
    title: 'Find HQ, help, and your next step',
    detail:
        'HQ opens your dashboard. Swipe the bottom navigation for Settings '
        'and Support. Settings > User\'s Guide contains the detailed manual '
        'and examples. Replay this welcome tour there whenever you like. '
        'Your first-steps checklist can be resumed or hidden; no invitation '
        'or successful match is required to complete the learning steps.',
  ),
];

Future<bool> saveFirstUse(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } catch (_) {
    // The service records diagnostics without account data.
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save guide progress. Please try again.'),
        ),
      );
    }
    return false;
  }
}

Future<void> replayFirstUse(BuildContext context) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sign in to replay the welcome tour.')),
    );
    return;
  }
  final service = FirstUseService.forUser(uid);
  if (!await saveFirstUse(context, () => service.startTour(restart: true)))
    return;
  if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
}

Future<void> openInvitationQr(BuildContext context) async {
  if (SimpleModePolicy.isActive) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Referrals is restricted in Simple Mode. Use the welcome '
          'tour to learn the steps without changing modes.',
        ),
      ),
    );
    return;
  }
  await Navigator.of(context).pushNamed('/referrals');
}

class FirstUseLearningLayout extends StatelessWidget {
  const FirstUseLearningLayout({
    super.key,
    required this.service,
    required this.tab,
    required this.onOpen,
    required this.keyboardVisible,
    required this.child,
  });
  final FirstUseService? service;
  final String tab;
  final ValueChanged<String> onOpen;
  final bool keyboardVisible;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        if (service case final progress?
            when progress.ready &&
                progress.enabled &&
                !progress.hidden &&
                !progress.touring &&
                !keyboardVisible)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * .30),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  FirstStepsCard(service: progress, onOpen: onOpen),
                  FirstUseFeatureTip(service: progress, tab: tab),
                ],
              ),
            ),
          ),
        Expanded(child: child),
      ],
    ),
  );
}

class FirstUseFeatureTip extends StatelessWidget {
  const FirstUseFeatureTip({
    super.key,
    required this.service,
    required this.tab,
  });
  final FirstUseService service;
  final String tab;

  @override
  Widget build(BuildContext context) {
    final stop = firstUseStops.where((stop) => stop.tab == tab).firstOrNull;
    if (stop == null || service.tipsSeen.contains(tab)) {
      return const SizedBox.shrink();
    }
    return Card(
      child: ExpansionTile(
        title: Text('First visit: $tab'),
        subtitle: const Text('Tap for tips about this screen.'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(stop.detail),
          TextButton(
            onPressed: () =>
                saveFirstUse(context, () => service.dismissTip(tab)),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class InvitationGuideCard extends StatelessWidget {
  const InvitationGuideCard({super.key});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Invite someone while you are together',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            '1. Explain what you use Prox for and ask whether they want to join.\n'
            '2. Tap Create in-person QR below and let them scan it to install.\n'
            '3. Stay together. After installation, reopen or refresh the QR '
            'to complete in-person verification.\n'
            '4. Both people must meet the location, expiry, consent, and '
            'eligibility checks. Only include a Party invitation if you intend it.\n\n'
            'A new account needs the in-person verification flow for full '
            'access; downloading or entering an ordinary code alone is not '
            'enough. More local participants can improve opportunities, but '
            'you never need to recruit a quota of people. Matches, Party '
            'membership, and rewards are not guaranteed.',
          ),
          TextButton(
            onPressed: () async {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sign in to save your learning progress.'),
                  ),
                );
                return;
              }
              final saved = await saveFirstUse(
                context,
                () => FirstUseService.forUser(uid).markComplete(['invitation']),
              );
              if (saved && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Invitation learning step completed. No invite was sent.',
                    ),
                  ),
                );
              }
            },
            child: const Text('I understand these steps'),
          ),
        ],
      ),
    ),
  );
}

class FirstUseWelcomeGate extends StatefulWidget {
  const FirstUseWelcomeGate({
    super.key,
    required this.service,
    required this.autoWelcome,
    required this.child,
  });
  final FirstUseService service;
  final bool autoWelcome;
  final Widget child;

  @override
  State<FirstUseWelcomeGate> createState() => _FirstUseWelcomeGateState();
}

class _FirstUseWelcomeGateState extends State<FirstUseWelcomeGate> {
  late Future<void> _load = widget.service.load(
    autoWelcome: widget.autoWelcome,
  );
  bool _busy = false;
  bool _skip = false;

  Future<void> _continue(bool tour) async {
    setState(() => _busy = true);
    await saveFirstUse(context, () => widget.service.welcome(startTour: tour));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _load,
    builder: (context, snapshot) {
      if (_skip) return widget.child;
      if (snapshot.hasError) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load your welcome guide.'),
                  TextButton(
                    onPressed: () => setState(() {
                      _load = widget.service.load(
                        autoWelcome: widget.autoWelcome,
                      );
                    }),
                    child: const Text('Retry'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _skip = true),
                    child: const Text('Continue without saving guide progress'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (widget.service.welcomeSeen) return widget.child;
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: AlertDialog(
              scrollable: true,
              title: const Text('Welcome to Prox'),
              content: const Text(firstUseWelcome),
              actions: [
                TextButton(
                  onPressed: _busy ? null : () => _continue(false),
                  child: const Text('Explore on my own'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _continue(true),
                  child: const Text('Show me how'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class FirstStepsCard extends StatelessWidget {
  const FirstStepsCard({
    super.key,
    required this.service,
    required this.onOpen,
  });
  final FirstUseService service;
  final ValueChanged<String> onOpen;

  static const tasks = <String, String>{
    'profile': 'Complete your profile',
    'keywords': 'Add Looking For and Can Provide keywords',
    'nearby': 'Explore Nearby',
    'connections': 'Learn requests, chat, and meetups',
    'invitation': 'Learn to share your in-person QR',
  };

  @override
  Widget build(BuildContext context) {
    final done = tasks.keys.where(service.completed.contains).length;
    return Card(
      child: ExpansionTile(
        title: Text('Your first steps: $done of ${tasks.length}'),
        subtitle: const Text('Learn at your pace. Invitations are optional.'),
        children: [
          for (final task in tasks.entries)
            ListTile(
              leading: Icon(
                service.completed.contains(task.key)
                    ? Icons.check_circle_outline
                    : Icons.radio_button_unchecked,
              ),
              title: Text(task.value),
              onTap: () => onOpen(task.key),
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => saveFirstUse(
                  context,
                  () => service.startTour(restart: service.finished),
                ),
                child: Text(service.finished ? 'Replay tour' : 'Resume tour'),
              ),
              TextButton(
                onPressed: () =>
                    saveFirstUse(context, () => service.setHidden(true)),
                child: const Text('Hide checklist'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FirstUseTourCard extends StatefulWidget {
  const FirstUseTourCard({
    super.key,
    required this.service,
    required this.locked,
  });
  final FirstUseService service;
  final bool locked;

  @override
  State<FirstUseTourCard> createState() => _FirstUseTourCardState();
}

class _FirstUseTourCardState extends State<FirstUseTourCard> {
  bool _busy = false;

  Future<void> _action(Future<void> Function() action) async {
    setState(() => _busy = true);
    await saveFirstUse(context, action);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _next() async {
    final service = widget.service;
    final step = service.step;
    final task = switch (step) {
      1 => 'nearby',
      2 => 'connections',
      4 => 'invitation',
      _ => null,
    };
    if (task != null) await service.markComplete([task]);
    if (step == firstUseStops.length - 1) {
      await service.finishTour();
    } else {
      await service.moveTo(step + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.service.step;
    final stop = firstUseStops[step];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) widget.service.pauseTour();
      },
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: 'Welcome tour',
        child: Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Welcome tour: ${step + 1} of ${firstUseStops.length}'),
                  const SizedBox(height: 8),
                  Text(
                    stop.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(stop.detail),
                  if (widget.locked) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'This tab is currently restricted in Simple Mode. '
                      'You can learn about it here without changing modes or '
                      'unlocking anything.',
                    ),
                  ],
                  if (step == 2)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<bool>(
                                builder: (_) =>
                                    const ReferralDemoWalkthroughScreen(
                                      allowExit: true,
                                    ),
                              ),
                            ),
                      child: const Text('Try the example walkthrough'),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (step > 0)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _action(
                                  () => widget.service.moveTo(step - 1),
                                ),
                          child: const Text('Back'),
                        ),
                      TextButton(
                        onPressed: _busy ? null : widget.service.pauseTour,
                        child: const Text('Finish later'),
                      ),
                      FilledButton(
                        onPressed: _busy ? null : () => _action(_next),
                        child: Text(
                          step == firstUseStops.length - 1
                              ? 'Finish tour'
                              : 'Next',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
