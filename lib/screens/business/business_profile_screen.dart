import 'package:flutter/material.dart';
import 'package:prox/screens/business/business_mode_setup_screen.dart';

/// The Pro tab edits the account's canonical profile, with the same preview and
/// entitlement checks as setup. There is no second business profile document.
class BusinessProfileScreen extends StatelessWidget {
  const BusinessProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => const BusinessModeSetupScreen();
}
