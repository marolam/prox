import "package:flutter/material.dart";
import "package:prox/screens/onboarding/quick_start_setup_screen.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/ui_telemetry_service.dart";

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  @override
  void initState() {
    super.initState();
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
      MaterialPageRoute<void>(builder: (_) => const QuickStartSetupScreen()),
    );
    ContextHelpService.instance.setContext(previous);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Welcome to Prox",
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Find nearby people who need what you offer or offer what you need. "
                "Start a conversation by agreement, then plan a safe public meetup.\n\n"
                "First, make it easy for others to understand you:",
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
                "Quick setup takes you through each required profile step.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _goQuickSetup(context),
                  child: const Text("Start quick setup"),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Your welcome tour and first-steps checklist will explain Nearby, "
                "chat, meetups, Party, and your invitation QR. You can finish "
                "learning later. Invite people who could benefit: a growing local "
                "community helps everyone, but invitations are optional.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
