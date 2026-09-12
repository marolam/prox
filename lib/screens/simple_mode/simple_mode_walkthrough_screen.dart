import "package:flutter/material.dart";

import "package:prox/screens/profile/profile_edit_screen.dart";
import "package:prox/screens/settings/discovery_settings_screen.dart";
import "package:prox/screens/settings/match_scope_settings_screen.dart";
import "package:prox/screens/support/support_hub_screen.dart";
import "package:prox/services/user_settings_service.dart";

class SimpleModeWalkthroughScreen extends StatefulWidget {
  const SimpleModeWalkthroughScreen({
    super.key,
    required this.onDone,
  });

  final VoidCallback onDone;

  @override
  State<SimpleModeWalkthroughScreen> createState() =>
      _SimpleModeWalkthroughScreenState();
}

class _SimpleModeWalkthroughScreenState
    extends State<SimpleModeWalkthroughScreen> {
  final PageController _controller = PageController();
  int _index = 0;
  bool _isAdvancing = false;

  static const int _lastIndex = 4;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_isAdvancing) return;

    if (_index >= _lastIndex) {
      UserSettingsService.instance.setSimpleModeStageIndex(5);
      UserSettingsService.instance.setSimpleModeCompleted(true);
      widget.onDone();
      return;
    }

    setState(() => _isAdvancing = true);
    UserSettingsService.instance.setSimpleModeStageIndex(_index + 1);
    try {
      await _controller.nextPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } finally {
      if (mounted) {
        setState(() => _isAdvancing = false);
      }
    }
  }

  Future<void> _openProfileSetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        // Keep users inside Simple Mode walkthrough after save.
        builder: (_) => const ProfileEditScreen(fromOnboarding: false),
      ),
    );
  }

  Future<void> _openDiscoveryFilters() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const DiscoverySettingsScreen(),
      ),
    );
  }

  Future<void> _openMatchScope() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const MatchScopeSettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text("Simple Mode walkthrough"),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Semantics(
                  excludeSemantics: true,
                  label: "Simple Mode setup progress",
                  value: "Step ${_index + 1} of ${_lastIndex + 1}",
                  child: LinearProgressIndicator(
                    value: (_index + 1) / (_lastIndex + 1),
                    minHeight: 7,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Semantics(
                liveRegion: true,
                child: Text(
                  "Step ${_index + 1} of ${_lastIndex + 1}",
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: PageView(
                  controller: _controller,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _index = i),
                  children: [
                    _stepCard(
                      context,
                      title: "How Simple Mode works",
                      message:
                          "Simple Mode removes extra noise and focuses on one next action at a time. You will still have full control, but we guide the order so you do not get overwhelmed.",
                      bullets: const [
                        "Keep settings minimal while learning",
                        "Use safer defaults by default",
                        "Follow profile -> nearby -> chat -> meetup flow",
                      ],
                    ),
                    _stepCard(
                      context,
                      title: "Step 1: Build your profile",
                      message:
                          "Your profile drives match quality. Add only essentials first: name, selfie, one Searching For keyword, and one Can Provide keyword.",
                      bullets: const [
                        "Specific keywords create better matches",
                        "A clear selfie improves trust",
                        "You can edit anytime later",
                      ],
                      actionLabel: "Open profile setup",
                      onAction: _openProfileSetup,
                    ),
                    _stepCard(
                      context,
                      title: "Step 2: Keep discovery simple",
                      message:
                          "Start narrow. Small radius plus normal passive mode keeps results clean while you learn how cards behave.",
                      bullets: const [
                        "Use discovery filters for radius",
                        "Use match scope for Party/Tree/Public visibility",
                        "Change one setting at a time",
                      ],
                      secondaryActionLabel: "Open discovery filters",
                      onSecondaryAction: _openDiscoveryFilters,
                      actionLabel: "Open match scope",
                      onAction: _openMatchScope,
                    ),
                    _stepCard(
                      context,
                      title: "Step 3: Follow the progression",
                      message:
                          "Once Nearby shows a useful card, request chat, confirm intent in messages, then propose a meetup in-app. This keeps the experience structured and safe.",
                      bullets: const [
                        "Nearby: identify relevant intent",
                        "Chat: confirm both sides are aligned",
                        "Meetup: plan and complete in-app",
                      ],
                    ),
                    _stepCard(
                      context,
                      title: "Step 4: You are ready",
                      message:
                          "Simple Mode is active. Continue with Home and follow the guided order. Need help later? Support is one tap away.",
                      bullets: const [
                        "You can switch modes in Settings",
                        "You can replay this flow by re-enabling Simple Mode",
                        "Use Support when uncertain",
                      ],
                      actionLabel: "Open support hub",
                      onAction: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SupportHubScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isAdvancing ? null : _next,
                    icon: Icon(_index >= _lastIndex
                        ? Icons.check_circle_outline
                        : Icons.arrow_forward),
                    label: Text(_index >= _lastIndex
                        ? "Finish Simple Mode setup"
                        : "Continue"),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepCard(
    BuildContext context, {
    required String title,
    required String message,
    required List<String> bullets,
    String? actionLabel,
    Future<void> Function()? onAction,
    String? secondaryActionLabel,
    Future<void> Function()? onSecondaryAction,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              for (final bullet in bullets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text("- $bullet", style: theme.textTheme.bodyMedium),
                ),
              if (secondaryActionLabel != null &&
                  onSecondaryAction != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onSecondaryAction,
                  icon: const Icon(Icons.tune),
                  label: Text(secondaryActionLabel),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.open_in_new),
                  label: Text(actionLabel),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
