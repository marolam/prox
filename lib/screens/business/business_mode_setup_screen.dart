import 'package:flutter/material.dart';
import 'package:prox/screens/profile/profile_edit_screen.dart';
import 'package:prox/screens/store/feature_example_screen.dart';
import 'package:prox/services/pro_mode_preview_access.dart';

/// Legacy setup links share the canonical profile editor and its entitlement
/// checks. Product examples remain available outside the limited live preview.
class BusinessModeSetupScreen extends StatelessWidget {
  const BusinessModeSetupScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      ProModePreviewAccess.instance.isAllowedForCurrentUser()
      ? const ProfileEditScreen(fromOnboarding: false)
      : const FeatureExampleScreen();
}
