import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter/material.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:permission_handler/permission_handler.dart";
import "package:geolocator/geolocator.dart";

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
import "package:prox/screens/settings/demo_mode_exports_screen.dart";
import "package:prox/screens/settings/match_scope_settings_screen.dart";
import "package:prox/screens/settings/privacy/blocked_users_screen.dart";
import "package:prox/screens/settings/support_feedback_screen.dart";
import "package:prox/screens/settings/user_guide_screen.dart";
import "package:prox/screens/settings/account/account_screen.dart";
import "package:prox/screens/profile/profile_edit_screen.dart";

import "package:prox/screens/trust/trust_rules_screen.dart";
import "package:prox/screens/trust/trust_timeline_screen.dart";

import "package:prox/services/build_info_service.dart";
import "package:prox/services/auth/auth_bootstrap.dart";
import "package:prox/bootstrap/nearby_bootstrap.dart";
import "package:prox/dev/dev_user_simulator_service.dart";
import "package:prox/services/changelog_service.dart";
import "package:prox/services/dev_matching_override_service.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/location_privacy_service.dart";
import "package:prox/services/push_notifications.dart";
import "package:prox/services/secure_credential_store.dart";
import "package:prox/services/tutorial/welcome_tutorial_service.dart";
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
  bool _tutorialPrefsLoaded = false;
  bool _tutorialDontShowAgain = false;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _loadTutorialPrefs();
  }

  Future<void> _loadTutorialPrefs() async {
    final tutorial = WelcomeTutorialService.instance;
    await tutorial.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _tutorialPrefsLoaded = true;
      _tutorialDontShowAgain = tutorial.dontShowAgain;
    });
  }

  Future<void> _setTutorialDontShowAgain(bool value) async {
    await WelcomeTutorialService.instance.setDontShowAgain(value);
    if (!mounted) return;
    setState(() {
      _tutorialPrefsLoaded = true;
      _tutorialDontShowAgain = value;
    });
  }

  Future<void> _replayQuickTutorial(BuildContext context) async {
    final tutorial = WelcomeTutorialService.instance;
    await tutorial.ensureLoaded();
    await tutorial.setDontShowAgain(false);

    if (!mounted) return;
    setState(() {
      _tutorialPrefsLoaded = true;
      _tutorialDontShowAgain = false;
    });

    tutorial.startCustomTutorial(const <WelcomeTutorialStep>[
      WelcomeTutorialStep(
        id: "profile_photo",
        screenId: "profile_edit",
        targetId: "photo_controls",
        actionId: "profile.add_photo",
        title: "Step 1: Add a clear photo",
        message:
            "Use Camera or Gallery. A real photo makes first meetups smoother and safer.",
      ),
      WelcomeTutorialStep(
        id: "profile_save",
        screenId: "profile_edit",
        targetId: "save_button",
        actionId: "profile.save_profile",
        title: "Step 2: Save profile",
        message:
            "Save your profile to unlock matching. Your keywords drive who appears nearby.",
      ),
      WelcomeTutorialStep(
        id: "first_match",
        screenId: "matches",
        targetId: "first_match_card",
        actionId: "matches.open_first_chat",
        title: "Step 3: Your first match",
        message:
            "Tap the highlighted match to start your first chat. Prox focuses on nearby, intent-based connections so conversations can become real meetups.",
      ),
    ]);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Tutorial replay started. Complete profile steps to continue.")),
    );

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ProfileEditScreen(fromOnboarding: false),
      ),
    );
  }

  Future<void> _spawnDemoUsers(BuildContext context) async {
    try {
      GeoPoint? center;
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        center = GeoPoint(last.latitude, last.longitude);
      } else {
        final cur = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            distanceFilter: 25,
            timeLimit: Duration(seconds: 3),
          ),
        );
        center = GeoPoint(cur.latitude, cur.longitude);
      }

      DevUserSimulatorService.instance.spawnPreset(10, around: center);
      await proxRestartNearby();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Spawned 10 simulated nearby users for demo testing.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not spawn demo users: $e")),
      );
    }
  }

  Future<void> _resetDemoTestingState(BuildContext context) async {
    try {
      final svc = UserSettingsService.instance;
      svc.setDemoSimulatedNearbyLocationEnabled(false);
      svc.setDemoSimulatedNearbyOffsetMiles(0.25);
      svc.setDemoForceMatchAllWithinRadius(false);
      svc.setDemoFastPresenceRefreshEnabled(false);
      svc.setDemoModeEnabled(false);

      await DevMatchingOverrideService.instance.setUnlimitedRadius(false);
      DevUserSimulatorService.instance.stop();
      await proxRestartNearby();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Demo testing state reset to defaults.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Demo reset failed: $e")),
      );
    }
  }

  Future<void> _pushWithHelpContext(
    BuildContext context, {
    required String contextKey,
    required Widget page,
  }) async {
    ContextHelpService.instance.setContext(contextKey);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
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
    if (snap.permission == LocationPermission.deniedForever) return "Permission blocked";
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
                    style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 14),

                AnimatedBuilder(
                  animation: LocationPrivacyService.instance,
                  builder: (_, __) {
                    final enabled = LocationPrivacyService.instance.locationEnabled;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outline.withValues(alpha: 0.20)),
                      ),
                      child: Row(
                        children: [
                          Icon(enabled ? Icons.toggle_on : Icons.toggle_off, color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              enabled ? "Location enabled in Prox" : "Location disabled in Prox",
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Switch(
                            value: enabled,
                            onChanged: (v) {
                              // ignore: discarded_futures
                              LocationPrivacyService.instance.setLocationEnabled(v);
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
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "- We do not share your exact GPS coordinates with other users\n"
                    "- We do not sell your location data\n"
                    "- We do not continuously track you when you are inactive",
                    style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
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
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Build", style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
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
                  child: Text("What changed", style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                for (final e in entries) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      e.title,
                      style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
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
        const SnackBar(content: Text("Signing out..."), duration: Duration(seconds: 1)),
      );
    }

    final List<String> warnings = <String>[];
    try {
      final String uidBefore = FirebaseAuth.instance.currentUser?.uid ?? "";

      // Sign out first so logout is never blocked by cleanup side effects.
      await FirebaseAuth.instance.signOut().timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw TimeoutException("auth sign-out timed out"),
      );

      try {
        await AuthBootstrap.instance
            .prepareForManualSignOut()
            .timeout(const Duration(seconds: 3), onTimeout: () {});
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

      try {
        await SecureCredentialStore.instance
            .setEnabled(false)
            .timeout(const Duration(seconds: 2), onTimeout: () {});
      } catch (_) {
        warnings.add("disable saved login");
      }

      try {
        await SecureCredentialStore.instance
            .clearCredentials()
            .timeout(const Duration(seconds: 3), onTimeout: () {});
      } catch (_) {
        warnings.add("credential cleanup");
      }

      if (navigator.mounted) {
        navigator.pushNamedAndRemoveUntil("/auth", (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Log out failed: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _signingOut = false);
      }
    }

    if (warnings.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Logged out with warnings: ${warnings.join(", ")}")),
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
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Log out")),
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
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.2),
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
                  subtitle: "Ambient discovery field (no pins). Requires a crowd threshold before it shows anything.",
                  value: settings.trustPulseEnabled,
                  onChanged: (v) => UserSettingsService.instance.setTrustPulseEnabled(v),
                ),
                _toggleCard(
                  context,
                  icon: Icons.auto_awesome,
                  title: "Referral signal",
                  subtitle: "Show/hide the 'Introduced by...' warming signal. Referrals never block entry.",
                  value: settings.referralSignalEnabled,
                  onChanged: (v) => UserSettingsService.instance.setReferralSignalEnabled(v),
                ),
                _toggleCard(
                  context,
                  icon: Icons.science_outlined,
                  title: "Demo Mode (simulated location)",
                  subtitle: "Default OFF. Shows a persistent watermark and marks demo exports as SIMULATED.",
                  value: settings.demoModeEnabled,
                  onChanged: (v) => UserSettingsService.instance.setDemoModeEnabled(v),
                ),
                if (settings.demoModeEnabled)
                  _toggleCard(
                    context,
                    icon: Icons.near_me_outlined,
                    title: "Demo nearby location offset",
                    subtitle: "Write a simulated location offset near your real position (up to 1 mile) for safer QA runs.",
                    value: settings.demoSimulatedNearbyLocationEnabled,
                    onChanged: (v) => UserSettingsService.instance.setDemoSimulatedNearbyLocationEnabled(v),
                  ),
                if (settings.demoModeEnabled && settings.demoSimulatedNearbyLocationEnabled)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.route_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Simulated offset distance",
                                style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            Text(
                              "${settings.demoSimulatedNearbyOffsetMiles.toStringAsFixed(2)} mi",
                              style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Keeps demo location near your actual location while still being clearly simulated.",
                          style: textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          value: settings.demoSimulatedNearbyOffsetMiles,
                          min: 0.0,
                          max: 1.0,
                          divisions: 20,
                          label: "${settings.demoSimulatedNearbyOffsetMiles.toStringAsFixed(2)} mi",
                          onChanged: (v) => UserSettingsService.instance.setDemoSimulatedNearbyOffsetMiles(v),
                        ),
                      ],
                    ),
                  ),
                if (settings.demoModeEnabled)
                  _toggleCard(
                    context,
                    icon: Icons.groups_2_outlined,
                    title: "Force auto-match in radius",
                    subtitle: "Bypass keyword/mode filters and auto-match everyone already inside your configured radius.",
                    value: settings.demoForceMatchAllWithinRadius,
                    onChanged: (v) => UserSettingsService.instance.setDemoForceMatchAllWithinRadius(v),
                  ),
                if (settings.demoModeEnabled)
                  _toggleCard(
                    context,
                    icon: Icons.speed_outlined,
                    title: "Fast presence refresh",
                    subtitle: "Increase presence update frequency for quicker QA feedback loops.",
                    value: settings.demoFastPresenceRefreshEnabled,
                    onChanged: (v) {
                      UserSettingsService.instance.setDemoFastPresenceRefreshEnabled(v);
                      unawaited(proxRestartNearby());
                    },
                  ),
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Demo testing actions",
                        style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        settings.demoModeEnabled
                            ? "Spawn simulated users or reset all demo overrides."
                            : "Turn on Demo Mode above to enable these actions.",
                        style: textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: settings.demoModeEnabled
                                ? () => _spawnDemoUsers(context)
                                : null,
                            icon: const Icon(Icons.group_add_outlined),
                            label: const Text("Spawn 10 nearby users"),
                          ),
                          OutlinedButton.icon(
                            onPressed: settings.demoModeEnabled
                                ? () => _resetDemoTestingState(context)
                                : null,
                            icon: const Icon(Icons.restart_alt_outlined),
                            label: const Text("Reset demo state"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.text_fields, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "Text size",
                              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(
                            "${settings.textScaleFactor.toStringAsFixed(2)}x",
                            style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
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
                        onChanged: (v) => UserSettingsService.instance.setTextScaleFactor(v),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),
                const ModeSwitchCard(),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text("Tutorial", style: textTheme.titleMedium),
                ),
                ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: const Text("Replay quick tutorial"),
                  subtitle: const Text("Guided profile and first-match walkthrough."),
                  onTap: () => _replayQuickTutorial(context),
                ),
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: const Text("User's Guide"),
                  subtitle: const Text("One-tap guide with feature pipelines and quick entry points."),
                  onTap: () async {
                    await _pushWithHelpContext(
                      context,
                      contextKey: "settings:user_guide",
                      page: const UserGuideScreen(),
                    );
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.visibility_off_outlined),
                  title: const Text("Don't show tutorial automatically"),
                  subtitle: const Text("You can always replay it from Settings."),
                  value: _tutorialDontShowAgain,
                  onChanged: _tutorialPrefsLoaded ? _setTutorialDontShowAgain : null,
                ),

                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text("Cosmetics"),
                  subtitle: const Text("Themes and UI flair (never affects trust)."),
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
                    subtitle: const Text("See confirmations logged on this device."),
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
                  subtitle: const Text("Test account + step-by-step review path + screencast checklist."),
                  onTap: () async {
                    await _pushWithHelpContext(
                      context,
                      contextKey: "settings:review_survival_kit",
                      page: const AppReviewSurvivalKitScreen(),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.route_outlined),
                  title: const Text("Demo trace exports"),
                  subtitle: const Text("README + CSV + JSON with explicit SIMULATED provenance."),
                  onTap: () async {
                    await _pushWithHelpContext(
                      context,
                      contextKey: "settings:demo_trace_exports",
                      page: const DemoModeExportsScreen(),
                    );
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.support_agent_outlined),
                  title: const Text("Support Mode"),
                  subtitle: const Text("Opt-in volunteer support (queue + audits coming next)."),
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
                  subtitle: const Text("Code of conduct, violations, and the appeal process."),
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
                  subtitle: const Text("Your incident drafts, submissions, and decisions."),
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
                  subtitle: const Text("Match scope, Tree depth, and distance precision."),
                  onTap: () async {
                    await _pushWithHelpContext(
                      context,
                      contextKey: "settings:match_scope",
                      page: const MatchScopeSettingsScreen(),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.radar),
                  title: const Text("Discovery filters"),
                  subtitle: const Text("Adjust radius and Business Mode filters for nearby matches."),
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
                  subtitle: const Text("Always-available activation path (no dead ends)."),
                  onTap: () async {
                    ContextHelpService.instance.setContext("settings:business_mode_payments");
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
                  subtitle: const Text("See what affected your trust - as a simple story."),
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
                  subtitle: const Text("Set a short away message for your Business avatar helper."),
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
                  subtitle: const Text("Manage meetup-request blocks (local-only for now)."),
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
                  subtitle: const Text("Payments, subscription, and Prox Points wallet."),
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
                  subtitle: const Text("Report bugs, request features, or ask for help."),
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
                  subtitle: const Text("Version, release info, and what changed."),
                  onTap: () => _showBuildInfoSheet(context),
                ),

                const SizedBox(height: 24),
                const Divider(),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text("Account", style: textTheme.titleMedium),
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
                  subtitle: Text(_signingOut ? "Signing out..." : "Sign out on this device."),
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
