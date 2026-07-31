import 'package:flutter/material.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/services/pro_mode_preview_access.dart';
import 'package:prox/services/user_settings_service.dart';
import 'business_mode_screen.dart';

class BusinessModeEntryScreen extends StatelessWidget {
  const BusinessModeEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!ProModePreviewAccess.instance.isAllowedForCurrentUser()) {
      UserSettingsService.instance.setUxMode(AppUxMode.party);
      return Scaffold(
        appBar: AppBar(title: const Text('Pro Mode')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Pro Mode preview is not available for this account.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return const BusinessModeScreen();
  }
}
