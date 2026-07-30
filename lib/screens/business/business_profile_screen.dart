import "package:flutter/material.dart";

import "package:prox/screens/business/business_mode_setup_screen.dart";
import "package:prox/screens/profile/profile_edit_screen.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/business_mode_service.dart";

class BusinessProfileScreen extends StatefulWidget {
  const BusinessProfileScreen({super.key});

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    BusinessModeService.instance.loadBusinessData();
  }

  Future<void> _pushWithHelpContext({
    required String contextKey,
    required Widget page,
  }) async {
    final previous = ContextHelpService.instance.contextKey.value;
    ContextHelpService.instance.setContext(contextKey);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    ContextHelpService.instance.setContext(previous);
  }

  void _openBusinessSetup() {
    // ignore: discarded_futures
    _pushWithHelpContext(
      contextKey: "business:setup",
      page: const BusinessModeSetupScreen(),
    );
  }

  void _openProfileEdit() {
    // ignore: discarded_futures
    _pushWithHelpContext(
      contextKey: "business:profile_edit",
      page: const ProfileEditScreen(fromOnboarding: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget card(Widget child) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
          ),
          child: child,
        );

    return Scaffold(
      appBar: AppBar(title: const Text("Business profile")),
      body: AnimatedBuilder(
        animation: BusinessModeService.instance,
        builder: (context, _) {
          final service = BusinessModeService.instance;
          final profile = service.profile;
          final subscription = service.subscription;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Business info", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    if (profile == null) ...[
                      Text(
                        "No business profile yet. Create one to start showing up in Business Mode.",
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _openBusinessSetup,
                        icon: const Icon(Icons.work_outline),
                        label: const Text("Create business profile"),
                      ),
                    ] else ...[
                      Text(profile.businessName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                      if ((profile.businessCategory ?? "").trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(profile.businessCategory!, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                      if ((profile.businessDescription ?? "").trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(profile.businessDescription!, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.3)),
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _openBusinessSetup,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text("Edit business info"),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Subscription", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (subscription == null) ...[
                      Text("No active subscription", style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ] else ...[
                      Text(
                        "${subscription.tier.displayName} active",
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Public profile", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                      "Update your name, headline, keywords, and availability.",
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _openProfileEdit,
                      icon: const Icon(Icons.person_outline),
                      label: const Text("Edit public profile"),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
