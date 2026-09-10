import "dart:async";

import "package:flutter/material.dart";
import "package:prox/screens/settings/account_privacy_screen.dart";
import "package:prox/services/runtime_diagnostics_service.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:geolocator/geolocator.dart";
import "package:permission_handler/permission_handler.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/screens/location/location_disclosure_screen.dart";
import "package:prox/screens/monetization/business_paywall_screen.dart";
import "package:prox/screens/review/app_review_survival_kit_screen.dart";

import "package:prox/screens/support/support_mode_hub_screen.dart";
import "package:prox/screens/policy/policy_hub_screen.dart";
import "package:prox/screens/incident/my_incidents_screen.dart";

import "package:prox/screens/settings/business_action_receipts_screen.dart";
import "package:prox/screens/settings/business_avatar_settings_screen.dart";
import "package:prox/screens/settings/cosmetics_screen.dart";
import "package:prox/screens/settings/discovery_settings_screen.dart";
import "package:prox/screens/settings/match_scope_settings_screen.dart";
import "package:prox/screens/settings/privacy/blocked_users_screen.dart";
import "package:prox/screens/settings/support_feedback_screen.dart";
import "package:prox/screens/settings/sound_alert_settings_screen.dart";
import "package:prox/screens/settings/party_profile_sharing_screen.dart";
import "package:prox/screens/settings/user_guide_screen.dart";
import "package:prox/screens/settings/account/account_screen.dart";

import "package:prox/screens/trust/trust_rules_screen.dart";
import "package:prox/screens/trust/trust_timeline_screen.dart";

import "package:prox/services/build_info_service.dart";
import "package:prox/services/auth/auth_bootstrap.dart";
import "package:prox/services/changelog_service.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/login_update_check_service.dart";
import "package:prox/services/location_privacy_service.dart";
import "package:prox/services/push_notifications.dart";
import "package:prox/services/secure_credential_store.dart";
import "package:prox/services/user_settings_service.dart";

import "package:prox/widgets/build_info_badge.dart";
import "package:prox/widgets/mode_switch_card.dart";
import "package:prox/widgets/prox_trust_bar.dart";

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _signingOut = false;

  Future<void> _pushWithHelpContext(
    BuildContext context, {
    required String contextKey,
    required Widget page,
  }) async {
    ContextHelpService.instance.setContext(contextKey);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    ContextHelpService.instance.setContext("home:settings");
  }

  Future<void> _openLocationDisclosure(BuildContext context) async {
    await _pushWithHelpContext(
      context,
      contextKey: "settings:location_privacy_disclosure",
      page: const LocationDisclosureScreen(showAppBar: true),
    );
  }

  Future<void> _openSystemSettings() async {
    await openAppSettings();
  }

  Future<String> _locationStatusLabel() async {
    await LocationPrivacyService.instance.ensureLoaded();
    final snap = await LocationPrivacyService.instance.snapshot();

    if (!LocationPrivacyService.instance.locationEnabled) return "Off in Prox";
    if (!snap.serviceEnabled) return "Phone location OFF";
    if (snap.permission == LocationPermission.deniedForever)
      return "Permission blocked";
    if (snap.isGranted) return "Enabled";
    return "Not granted";
  }

  void _showLocationInfoSheet(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final ColorScheme cs = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Location & privacy",
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Prox uses location for nearby discovery and meetups.",
                    style: textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "- Nearby discovery uses low-power location to show who's actually nearby.\n"
                    "- Meetups can use precise location briefly to help navigate and confirm arrival.\n"
                    "- You can turn location off in Prox anytime.",
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                AnimatedBuilder(
                  animation: LocationPrivacyService.instance,
                  builder: (_, __) {
                    final enabled =
                        LocationPrivacyService.instance.locationEnabled;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: cs.outline.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            enabled ? Icons.toggle_on : Icons.toggle_off,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              enabled
                                  ? "Location enabled in Prox"
                                  : "Location disabled in Prox",
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Switch(
                            value: enabled,
                            onChanged: (v) async {
                              try {
                                await LocationPrivacyService.instance
                                    .setLocationEnabled(v);
                              } catch (error, stack) {
                                RuntimeDiagnosticsService.instance.record(
                                  error,
                                  stack,
                                  operation: "Save location preference",
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "Your location choice applies now, but could not be saved. Try again before restarting Prox.",
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openLocationDisclosure(ctx),
                    icon: const Icon(Icons.article_outlined),
                    label: const Text("View disclosure again"),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openSystemSettings,
                    icon: const Icon(Icons.settings),
                    label: const Text("Open phone settings"),
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "What Prox does NOT do:",
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "- We do not share your exact GPS coordinates with other users\n"
                    "- We do not sell your location data\n"
                    "- We do not continuously track you when you are inactive",
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text("Done"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showBuildInfoSheet(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final TextTheme tt = theme.textTheme;

    final info = BuildInfoService.instance.info;
    final List<ChangelogEntry> entries = ChangelogService.instance.entries();

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Build & changelog",
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Build",
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: BuildInfoBadge(showBuiltAt: true, center: false),
                ),
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Built at: ${info.builtAt.millisecondsSinceEpoch <= 0 ? "unknown" : info.builtAt.toLocal().toString()}",
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "What changed",
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                for (final e in entries) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      e.title,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      e.bullets.map((b) => "- $b").join("\n"),
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final result = await LoginUpdateCheckService.instance
                          .check(forceRefresh: true);
                      if (!ctx.mounted) return;

                      if (result.checkFailed && !result.updateAvailable) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "Couldn't check for updates. Check your connection and try again.",
                            ),
                          ),
                        );
                        return;
                      }

                      final upToDate =
                          LoginUpdateCheckService.instance.compareVersions(
                            result.latestVersion,
                            result.currentVersion,
                          ) <=
                          0;
                      if (upToDate) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            duration: const Duration(seconds: 4),
                            content: Text(
                              "You are already on the latest version "
                              "(installed: v${result.currentVersion}, "
                              "release: v${result.latestVersion}). "
                              "If you expected an update, check the release artifact.",
                            ),
                          ),
                        );
                        return;
                      }

                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          duration: const Duration(seconds: 3),
                          content: Text(
                            "Installed: v${result.currentVersion} • "
                            "Latest: v${result.latestVersion}",
                          ),
                        ),
                      );

                      await LoginUpdateCheckService.instance.openLatestUpdate(
                        ctx,
                        preferredUrl: result.downloadUrl,
                        targetVersion: result.latestVersion,
                      );

                      if (!ctx.mounted) return;
                      // Keep existing version feedback after opening the updater URL.
                      await LoginUpdateCheckService.instance.checkAndNotify(
                        ctx,
                        forceRefresh: true,
                      );
                    },
                    icon: const Icon(Icons.system_update_alt_outlined),
                    label: const Text("Update to latest"),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text("Done"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _signOut(BuildContext context) async {
    if (_signingOut) return;

    final NavigatorState navigator = Navigator.of(context);
    setState(() => _signingOut = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Signing out..."),
          duration: Duration(seconds: 1),
        ),
      );
    }

    final List<String> warnings = <String>[];
    try {
      final String uidBefore = FirebaseAuth.instance.currentUser?.uid ?? "";

      try {
        await AuthBootstrap.instance.prepareForManualSignOut().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
      } catch (_) {
        warnings.add("auth bootstrap cleanup");
      }

      final String uid = uidBefore;
      if (uid.isNotEmpty) {
        try {
          await PushNotifications.instance
              .signOutCleanup(uid)
              .timeout(const Duration(seconds: 4), onTimeout: () {});
        } catch (_) {
          warnings.add("push cleanup");
        }
      }

      // Revoke the device token while Firestore still recognizes this account.
      // Cleanup is bounded above, so an offline network cannot prevent logout.
      await FirebaseAuth.instance.signOut().timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw TimeoutException("auth sign-out timed out"),
      );

      try {
        await SecureCredentialStore.instance
            .setEnabled(false)
            .timeout(const Duration(seconds: 2), onTimeout: () {});
      } catch (_) {
        warnings.add("disable saved login");
      }

      try {
        await SecureCredentialStore.instance.clearCredentials().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
      } catch (_) {
        warnings.add("credential cleanup");
      }

      if (navigator.mounted) {
        navigator.pushNamedAndRemoveUntil("/auth", (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Log out failed: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => _signingOut = false);
      }
    }

    if (warnings.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Logged out with warnings: ${warnings.join(", ")}"),
        ),
      );
    }
  }

  Future<void> _confirmAndSignOut(BuildContext context) async {
    if (_signingOut) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Log out?"),
        content: const Text("You will be signed out on this device."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Log out"),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      await _signOut(context);
    }
  }

  Widget _toggleCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    // ignore: discarded_futures
    LocationPrivacyService.instance.ensureLoaded();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings & Modes"),
        actions: [
          IconButton(
            tooltip: "Log out",
            onPressed: _signingOut ? null : () => _confirmAndSignOut(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder<UserSettings>(
        stream: UserSettingsService.instance.watch(),
        builder: (context, snap) {
          final settings = snap.data ?? UserSettingsService.instance.current;
          final bool isBusiness = settings.uxMode == AppUxMode.business;

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Trust", style: textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const ProxTrustBar(),
                  ],
                ),
              ),
              _toggleCard(
                context,
                icon: Icons.blur_on,
                title: "Trust Pulse overlay",
                subtitle:
                    "Ambient discovery field (no pins). Requires a crowd threshold before it shows anything.",
                value: settings.trustPulseEnabled,
                onChanged: (v) =>
                    UserSettingsService.instance.setTrustPulseEnabled(v),
              ),
              _toggleCard(
                context,
                icon: Icons.auto_awesome,
                title: "Referral signal",
                subtitle:
                    "Show/hide the 'Introduced by...' warming signal. Referrals never block entry.",
                value: settings.referralSignalEnabled,
                onChanged: (v) =>
                    UserSettingsService.instance.setReferralSignalEnabled(v),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.text_fields,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Text size",
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          "${settings.textScaleFactor.toStringAsFixed(2)}x",
                          style: textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Increase text size for readability across the app.",
                      style: textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Slider(
                      value: settings.textScaleFactor,
                      min: 0.9,
                      max: 1.6,
                      divisions: 7,
                      label: "${settings.textScaleFactor.toStringAsFixed(2)}x",
                      onChanged: (v) =>
                          UserSettingsService.instance.setTextScaleFactor(v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const ModeSwitchCard(),
              const SizedBox(height: 6),
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      value: settings.simpleModeEnabled,
                      title: const Text("Simple Mode"),
                      subtitle: const Text(
                        "Guided, lower-noise experience with safer defaults while learning.",
                      ),
                      onChanged: (enabled) {
                        UserSettingsService.instance.setSimpleModeEnabled(
                          enabled,
                        );
                        if (enabled) {
                          UserSettingsService.instance.setAlwaysUseNormalMode(
                            false,
                          );
                          UserSettingsService.instance.setSimpleModeCompleted(
                            true,
                          );
                          UserSettingsService.instance.setSimpleModeStageIndex(
                            0,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Simple Mode enabled. Only the guided Big-5 experience will be available.",
                              ),
                            ),
                          );
                        } else {
                          UserSettingsService.instance.setSimpleModeCompleted(
                            true,
                          );
                          UserSettingsService.instance.setSimpleModeStageIndex(
                            5,
                          );
                        }
                      },
                    ),
                    SwitchListTile.adaptive(
                      value: settings.alwaysUseNormalMode,
                      title: const Text("Always use Normal Mode"),
                      subtitle: const Text(
                        "Skip the login mode chooser and go straight to Normal Mode.",
                      ),
                      onChanged: (enabled) {
                        UserSettingsService.instance.setAlwaysUseNormalMode(
                          enabled,
                        );
                        if (enabled) {
                          UserSettingsService.instance.setSimpleModeEnabled(
                            false,
                          );
                          UserSettingsService.instance.setSimpleModeCompleted(
                            true,
                          );
                          UserSettingsService.instance.setSimpleModeStageIndex(
                            5,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text("Help", style: textTheme.titleMedium),
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text("User's Guide"),
                subtitle: const Text(
                  "One-tap guide with feature pipelines and quick entry points.",
                ),
                onTap: () async {
                  await _pushWithHelpContext(
                    context,
                    contextKey: "settings:user_guide",
                    page: const UserGuideScreen(),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text("Cosmetics"),
                subtitle: const Text(
                  "Themes and UI flair (never affects trust).",
                ),
                onTap: () async {
                  await _pushWithHelpContext(
                    context,
                    contextKey: "settings:cosmetics",
                    page: const CosmeticsScreen(),
                  );
                },
              ),
              if (isBusiness)
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text("Business receipts"),
                  subtitle: const Text(
                    "See confirmations logged on this device.",
                  ),
                  onTap: () async {
                    await _pushWithHelpContext(
                      context,
                      contextKey: "settings:business_receipts",
                      page: const BusinessActionReceiptsScreen(),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: const Text("App Review survival kit"),
                subtitle: const Text(
                  "Test account + step-by-step review path + screencast checklist.",
                ),
                onTap: () async {
                  await _pushWithHelpContext(
                    context,
                    contextKey: "settings:review_survival_kit",
                    page: const AppReviewSurvivalKitScreen(),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.support_agent_outlined),
                title: const Text("Support Mode"),
                subtitle: const Text(
                  "Practice with sample tickets and help others use Prox.",
                ),
                onTap: () async {
                  await _pushWithHelpContext(
                    context,
                    contextKey: "settings:support_mode",
                    page: const SupportModeHubScreen(),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.rule_outlined),
                title: const Text("Rules, enforcement & appeals"),
                subtitle: const Text(
                  "Code of conduct, violations, and the appeal process.",
                ),
                onTap: () async {
                  await _pushWithHelpContext(
                    context,
                    contextKey: "settings:policy_hub",
                    page: const PolicyHubScreen(),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.gavel_outlined),
                title: const Text("My reports & appeals"),
                subtitle: const Text(
                  "Your incident drafts, submissions, and decisions.",
                ),
                onTap: () async {
                  await _pushWithHelpContext(
                    context,
                    contextKey: "settings:my_incidents",
                    page: const MyIncidentsScreen(),
                  );
                },
              ),
              const SizedBox(height: 8),
              const Divider(height: 32),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text("Match settings"),
                subtitle: const Text(
                  "Match scope, Tree depth, and distance precision.",
                ),
                onTap: () async {
                  await _pushWithHelpContext(
                    context,
                    contextKey: "settings:match_scope",
                    page: const MatchScopeSettingsScreen(),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.volume_up_outlined),
                title: const Text("Sound & alerts"),
                subtitle: const Text("Match cues, volume, mute, and previews."),
                onTap: () async {
                  await _pushWithHelpContext(
                    context,
                    contextKey: "settings:sound_alerts",
                    page: const SoundAlertSettingsScreen(),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.group_outlined),
                title: const Text("Party profile sharing"),
                subtitle: const Text(
                  "Choose what mutual Party members can see about you.",
                ),
                onTap: () async {
                  await _pushWithHelpContext(
                    context,
                    contextKey: "settings:party_profile_sharing",
                    page: const PartyProfileSharingScreen(),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.radar),
                title: const Text("Discovery filters"),
                subtitle: const Text(
                  "Adjust radius and Business Mode filters for nearby matches.",
                ),
                onTap: () async {
                  await _pushWithHelpContext(
                    context,
                    contextKey: "settings:discovery_filters",
                    page: const DiscoverySettingsScreen(),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text("Business Mode & payments"),
                subtitle: const Text(
                  "Always-available activation path (no dead ends).",
                ),
                onTap: () async {
                  ContextHelpService.instance.setContext(
                    "settings:business_mode_payments",
                  );
                  await BusinessPaywallScreen.open(context);
                  ContextHelpService.instance.setContext("home:settings");
                },
              ),
              ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: const Text("Location & privacy"),
                subtitle: FutureBuilder<String>(
                  future: _locationStatusLabel(),
                  builder: (_, s) => Text(s.data ?? "Checking..."),
                ),
                onTap: () => _showLocationInfoSheet(context),
              ),
              ListTile(
                leading: const Icon(Icons.timeline),
                title: const Text("Trust timeline"),
                subtitle: const Text(
                  "See what affected your trust - as a simple story.",
                ),
                onTap: () async {
                  await _pushWithHelpContext(
                    context,
                    contextKey: "settings:trust_timeline",
                    page: const TrustTimelineScreen(),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text("Trust rulebook"),
                subtitle: const Text("Readable rules (no mystery math)."),
                onTap: () async {
                  await _pushWithHelpContext(
                    context,
                    contextKey: "settings:trust_rulebook",
                    page: const TrustRulesScreen(),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.smart_toy_outlined),
                title: const Text("Business avatar message"),
                subtitle: const Text(
                  "Set a short away message for your Business avatar helper.",
                ),
                onTap: () async {
                  await _pushWithHelpContext(
                    context,
                    contextKey: "settings:business_avatar",
                    page: const BusinessAvatarSettingsScreen(),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text("Blocked users"),
                subtitle: const Text(
                  "Manage the people you have blocked across your devices.",
                ),
                onTap: () async {
                  await _pushWithHelpContext(
                    context,
                    contextKey: "settings:blocked_users",
                    page: const BlockedUsersScreen(),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text("Account & billing"),
                subtitle: const Text(
                  "Payments, subscription, and Prox Points wallet.",
                ),
                onTap: () async {
                  await _pushWithHelpContext(
                    context,
                    contextKey: "settings:account_billing",
                    page: const AccountScreen(),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.support_agent_outlined),
                title: const Text("Support & feedback"),
                subtitle: const Text(
                  "Report bugs, request features, or ask for help.",
                ),
                onTap: () async {
                  await _pushWithHelpContext(
                    context,
                    contextKey: "settings:support_feedback",
                    page: const SupportFeedbackScreen(),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text("About"),
                subtitle: const Text(
                  "Version, release info, and what changed.",
                ),
                onTap: () => _showBuildInfoSheet(context),
              ),
              const SizedBox(height: 24),
              const Divider(),
              AnimatedBuilder(
                animation: RuntimeDiagnosticsService.instance,
                builder: (context, _) => SwitchListTile.adaptive(
                  title: const Text("Share crash reports"),
                  subtitle: const Text(
                    "Help fix crashes. Reports exclude your messages and profile details.",
                  ),
                  value: RuntimeDiagnosticsService.instance.sharingEnabled,
                  onChanged: (enabled) async {
                    try {
                      await RuntimeDiagnosticsService.instance
                          .setSharingEnabled(enabled);
                    } catch (_) {
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "Couldn't save that preference. Try again.",
                            ),
                          ),
                        );
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text("Account", style: textTheme.titleMedium),
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text("Your account data"),
                subtitle: const Text(
                  "Export an account summary or delete your account.",
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AccountPrivacyScreen(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  "Log out if you want to stop receiving notifications on this device or switch accounts.",
                  style: textTheme.bodySmall?.copyWith(
                    color: textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text("Log out"),
                subtitle: Text(
                  _signingOut ? "Signing out..." : "Sign out on this device.",
                ),
                trailing: _signingOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _signingOut ? null : () => _confirmAndSignOut(context),
              ),
            ],
          );
        },
      ),
    );
  }
}
