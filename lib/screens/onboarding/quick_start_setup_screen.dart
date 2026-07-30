import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:image_picker/image_picker.dart";

import "package:prox/services/image_picker_guard.dart";
import "package:prox/services/ui_telemetry_service.dart";
import "package:prox/services/user_profile_service.dart";
import "package:prox/shell/home_root_shell.dart";

class QuickStartSetupScreen extends StatefulWidget {
  const QuickStartSetupScreen({super.key});

  @override
  State<QuickStartSetupScreen> createState() => _QuickStartSetupScreenState();
}

class _QuickStartSetupScreenState extends State<QuickStartSetupScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _searching = TextEditingController();
  final TextEditingController _providing = TextEditingController();

  XFile? _photo;
  int _step = 0;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _searching.dispose();
    _providing.dispose();
    super.dispose();
  }

  Future<void> _pickSelfie() async {
    if (!ImagePickerGuard.tryAcquire()) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1400,
        imageQuality: 88,
      );
      if (picked == null || !mounted) return;
      setState(() => _photo = picked);
    } finally {
      ImagePickerGuard.release();
    }
  }

  bool _validateCurrentStep() {
    if (_step == 0) {
      return _name.text.trim().isNotEmpty;
    }
    if (_step == 1) {
      return _photo != null;
    }
    if (_step == 2) {
      return _searching.text.trim().isNotEmpty;
    }
    if (_step == 3) {
      return _providing.text.trim().isNotEmpty;
    }
    return true;
  }

  void _next() {
    if (!_validateCurrentStep()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please complete this step before continuing.")),
      );
      UiTelemetryService.instance.log(
        "quick_setup_step_blocked",
        meta: {"step": _step.toString()},
      );
      return;
    }
    if (_step < 3) {
      UiTelemetryService.instance.log(
        "quick_setup_step_completed",
        meta: {"step": _step.toString()},
      );
      setState(() => _step += 1);
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step -= 1);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_validateCurrentStep()) return;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.trim().isEmpty) return;

    setState(() => _saving = true);
    UiTelemetryService.instance.log("quick_setup_submit_start");
    try {
      final photoFile = _photo;
      if (photoFile == null) {
        throw StateError("Please select a selfie photo.");
      }

      final photoUrl = await UserProfileService.instance.uploadProfilePhoto(
        uid: uid,
        file: photoFile,
      );

      final searchingText = _searching.text.trim();
      final providingText = _providing.text.trim();

      await UserProfileService.instance.upsertProfile(
        uid: uid,
        displayName: _name.text.trim(),
        photoUrl: photoUrl,
        searchingText: searchingText,
        providingText: providingText,
        searchingFor: <String>[searchingText],
        canProvide: <String>[providingText],
      );

      if (!mounted) return;
      UiTelemetryService.instance.log("quick_setup_submit_success");
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const HomeRootShell()),
        (route) => false,
      );
    } catch (e) {
      UiTelemetryService.instance.log(
        "quick_setup_submit_failed",
        meta: {"error": e.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Quick setup failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Quick setup")),
      body: Stepper(
        currentStep: _step,
        onStepContinue: _step == 3 ? _save : _next,
        onStepCancel: _back,
        controlsBuilder: (context, details) {
          final bool last = _step == 3;
          return Row(
            children: [
              FilledButton(
                onPressed: _saving ? null : details.onStepContinue,
                child: Text(_saving ? "Saving..." : (last ? "Finish" : "Continue")),
              ),
              const SizedBox(width: 10),
              if (_step > 0)
                OutlinedButton(
                  onPressed: _saving ? null : details.onStepCancel,
                  child: const Text("Back"),
                ),
            ],
          );
        },
        steps: [
          Step(
            title: const Text("Name"),
            isActive: _step >= 0,
            content: TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: "Your name",
                hintText: "How people will see you in Prox",
              ),
            ),
          ),
          Step(
            title: const Text("Selfie"),
            isActive: _step >= 1,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_photo != null)
                  Text(
                    "Selected: ${_photo!.name}",
                    style: theme.textTheme.bodySmall,
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickSelfie,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(_photo == null ? "Choose selfie" : "Change selfie"),
                ),
              ],
            ),
          ),
          Step(
            title: const Text("Searching for"),
            isActive: _step >= 2,
            content: TextField(
              controller: _searching,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: "What do you want right now?",
                hintText: "Example: car jump, moving help, coffee meetup",
              ),
            ),
          ),
          Step(
            title: const Text("Can provide"),
            isActive: _step >= 3,
            content: TextField(
              controller: _providing,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: "What can you provide right now?",
                hintText: "Example: rideshare, tutoring, handyman help",
              ),
            ),
          ),
        ],
      ),
    );
  }
}
