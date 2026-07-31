import "package:flutter/material.dart";
import "package:prox/screens/profile/profile_edit_screen.dart";

class ProfileSetupScreen extends StatelessWidget {
  const ProfileSetupScreen({super.key});

  @override
  Widget build(BuildContext context) => const ProfileEditScreen(fromOnboarding: true);
}