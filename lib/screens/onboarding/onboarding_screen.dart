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
      body: SafeArea(
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
                "Quick setup takes you through each required profile step.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _goQuickSetup(context),
                  child: const Text("Start quick setup"),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "After your profile is created, open Referrals and complete the required Big-5 walkthrough.",
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
