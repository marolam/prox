import "package:flutter/material.dart";
import "package:prox/screens/onboarding/quick_start_setup_screen.dart";
import "package:prox/screens/profile/profile_edit_screen.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/tutorial/welcome_tutorial_service.dart";
import "package:prox/services/ui_telemetry_service.dart";
import "package:prox/widgets/tutorial/welcome_tutorial_bubble.dart";

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final GlobalKey _createProfileButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
  }

  Future<void> _goToProfile(BuildContext context, {required bool guided}) async {
    final tutorial = WelcomeTutorialService.instance;
    UiTelemetryService.instance.log(
      "onboarding_path_selected",
      meta: {"path": guided ? "guided_tutorial" : "profile_edit"},
    );
    UiTelemetryService.instance.log("onboarding_guided_selected");
    if (guided) {
      // ignore: discarded_futures
      tutorial.maybeStartFirstRunTutorial();
    }

    if (tutorial.active &&
        tutorial.isCurrentScreen("onboarding") &&
        !tutorial.isExpectedAction("onboarding.create_profile")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Quick tutorial: tap the highlighted button.")),
      );
      UiTelemetryService.instance.log(
        "onboarding_tutorial_gate_block",
        meta: {"reason": "expected_action_mismatch"},
      );
      return;
    }

    if (tutorial.active &&
        !(await tutorial.consumeExpectedAction("onboarding.create_profile"))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Quick tutorial: finish the current highlighted step first.")),
      );
      UiTelemetryService.instance.log(
        "onboarding_tutorial_gate_block",
        meta: {"reason": "consume_expected_failed"},
      );
      return;
    }

    final previous = ContextHelpService.instance.contextKey.value;
    ContextHelpService.instance.setContext("onboarding:profile_setup");
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ProfileEditScreen(fromOnboarding: true),
      ),
    );
    ContextHelpService.instance.setContext(previous);
  }

  Future<void> _goQuickSetup(BuildContext context) async {
    UiTelemetryService.instance.log(
      "onboarding_path_selected",
      meta: {"path": "quick_setup_4_steps"},
    );
    UiTelemetryService.instance.log("onboarding_quick_selected");
    final previous = ContextHelpService.instance.contextKey.value;
    ContextHelpService.instance.setContext("onboarding:quick_setup");
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const QuickStartSetupScreen(),
      ),
    );
    ContextHelpService.instance.setContext(previous);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Text(
                    "Welcome to Prox",
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Before you can start matching with people nearby, we need a few basics:",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    " Your name\n"
                    " A clear selfie\n"
                    " 1 Searching For keyword\n"
                    " 1 Can Provide keyword",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Choose your onboarding style:",
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Guided Tutorial: walkthrough with tips.\n"
                    "Quick Setup: 4 required steps (name, selfie, want, provide).",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: _createProfileButtonKey,
                      onPressed: () => _goToProfile(context, guided: true),
                      child: const Text("Start guided tutorial"),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _goQuickSetup(context),
                      child: const Text("Quick setup (4 steps)"),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Business Mode is optional and can be activated later.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          WelcomeTutorialBubble(
            screenId: "onboarding",
            targetKeys: <String, GlobalKey>{
              "create_profile_button": _createProfileButtonKey,
            },
          ),
        ],
      ),
    );
  }
}
