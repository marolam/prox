import "package:flutter/material.dart";

import "package:prox/screens/services/party_profile_service.dart";

class PartyProfileSharingScreen extends StatefulWidget {
  const PartyProfileSharingScreen({super.key});

  @override
  State<PartyProfileSharingScreen> createState() =>
      _PartyProfileSharingScreenState();
}

class _PartyProfileSharingScreenState extends State<PartyProfileSharingScreen> {
  final _about = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _area = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _shareAbout = false;
  bool _shareEmail = false;
  bool _sharePhone = false;
  bool _shareArea = false;
  bool _shareHeadline = false;
  bool _shareKeywords = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await PartyProfileService.instance.loadMine();
      if (!mounted) return;
      _about.text = value.about;
      _email.text = value.contactEmail;
      _phone.text = value.phone;
      _area.text = value.generalArea;
      setState(() {
        _shareAbout = value.shareAbout;
        _shareEmail = value.shareContactEmail;
        _sharePhone = value.sharePhone;
        _shareArea = value.shareGeneralArea;
        _shareHeadline = value.shareHeadline;
        _shareKeywords = value.shareKeywords;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await PartyProfileService.instance.saveMine(PartyProfileSharing(
        about: _about.text,
        contactEmail: _email.text,
        phone: _phone.text,
        generalArea: _area.text,
        shareAbout: _shareAbout,
        shareContactEmail: _shareEmail,
        sharePhone: _sharePhone,
        shareGeneralArea: _shareArea,
        shareHeadline: _shareHeadline,
        shareKeywords: _shareKeywords,
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Party profile sharing saved.")),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not save sharing settings.")),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field({
    required String title,
    required TextEditingController controller,
    required bool shared,
    required ValueChanged<bool> onChanged,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: title,
              border: const OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text("Share $title"),
            subtitle: const Text("Visible only to mutual Party members."),
            value: shared,
            onChanged: controller.text.trim().isEmpty ? null : onChanged,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _about.dispose();
    _email.dispose();
    _phone.dispose();
    _area.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Party profile sharing")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                const Text(
                  "Everything below is private until you choose to share it. "
                  "Shared information is available only to people who are in "
                  "your Party and have you in theirs.",
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Share profile headline"),
                  subtitle: const Text("Uses the headline on your profile."),
                  value: _shareHeadline,
                  onChanged: (v) => setState(() => _shareHeadline = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Share wants and has keywords"),
                  subtitle: const Text("Uses your current matching keywords."),
                  value: _shareKeywords,
                  onChanged: (v) => setState(() => _shareKeywords = v),
                ),
                const Divider(height: 32),
                _field(
                  title: "About me",
                  controller: _about,
                  shared: _shareAbout,
                  maxLines: 4,
                  onChanged: (v) => setState(() => _shareAbout = v),
                ),
                _field(
                  title: "General area",
                  controller: _area,
                  shared: _shareArea,
                  onChanged: (v) => setState(() => _shareArea = v),
                ),
                _field(
                  title: "Contact email",
                  controller: _email,
                  shared: _shareEmail,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (v) => setState(() => _shareEmail = v),
                ),
                _field(
                  title: "Phone number",
                  controller: _phone,
                  shared: _sharePhone,
                  keyboardType: TextInputType.phone,
                  onChanged: (v) => setState(() => _sharePhone = v),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text("Save sharing settings"),
                ),
              ],
            ),
    );
  }
}
