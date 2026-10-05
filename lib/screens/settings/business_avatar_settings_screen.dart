import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:prox/services/business_mode/business_avatar_settings_service.dart';

class BusinessAvatarSettingsScreen extends StatefulWidget {
  const BusinessAvatarSettingsScreen({
    super.key,
    this.settingsStore,
  });

  final BusinessAvatarSettingsStore? settingsStore;

  @override
  State<BusinessAvatarSettingsScreen> createState() =>
      _BusinessAvatarSettingsScreenState();
}

class _BusinessAvatarSettingsScreenState
    extends State<BusinessAvatarSettingsScreen> {
  late final BusinessAvatarSettingsStore _settingsStore;
  final _message = TextEditingController(text: defaultBusinessAvatarReply);
  bool _enabled = false;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _settingsStore =
        widget.settingsStore ?? BusinessAvatarSettingsService.instance;
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    try {
      final settings = await _settingsStore
          .loadForCurrentUser()
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      _message.text = settings.reply;
      setState(() {
        _enabled = settings.enabled;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    final reply = _message.text.trim();
    if (reply.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write a reply message before saving.')),
      );
      return;
    }

    if (mounted) setState(() => _saving = true);
    try {
      await _settingsStore
          .saveForCurrentUser(enabled: _enabled, reply: reply)
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business avatar reply saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save settings: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Business avatar reply')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Business avatar reply')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Business avatar reply')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Set the reply your business avatar can use when you are unavailable. This is saved to your account.',
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable business avatar reply'),
            subtitle: const Text(
              'When enabled, your saved message is ready for business follow-ups.',
            ),
            value: _enabled,
            onChanged: _saving ? null : (v) => setState(() => _enabled = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _message,
            maxLength: 280,
            minLines: 3,
            maxLines: 6,
            enabled: !_saving,
            decoration: const InputDecoration(labelText: 'Reply message'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text(
            'Conversation preview',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.person_outline),
              title: Text('Customer'),
              subtitle: Text('Are you available to help this afternoon?'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.smart_toy_outlined),
              title: Text(
                _enabled ? 'Business avatar reply' : 'Business avatar disabled',
              ),
              subtitle: Text(
                !_enabled
                    ? 'Enable the business avatar reply to use this message.'
                    : (_message.text.trim().isEmpty
                          ? 'Write a reply message to preview it here.'
                          : _message.text.trim()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy message'),
                  onPressed: _message.text.trim().isEmpty || _saving
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: _message.text.trim()),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Reply message copied.'),
                              ),
                            );
                          }
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving...' : 'Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
