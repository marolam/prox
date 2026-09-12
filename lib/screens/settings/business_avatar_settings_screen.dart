import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BusinessAvatarSettingsScreen extends StatefulWidget {
  const BusinessAvatarSettingsScreen({super.key});
  @override
  State<BusinessAvatarSettingsScreen> createState() =>
      _BusinessAvatarSettingsScreenState();
}

class _BusinessAvatarSettingsScreenState
    extends State<BusinessAvatarSettingsScreen> {
  final _message = TextEditingController(
    text:
        'Thanks for reaching out! I am away right now and will reply when I am available.',
  );
  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Business reply example')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Try a business away message. This example is local; it does not enable an avatar or send automated messages.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _message,
          maxLength: 280,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Away message'),
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
            title: Text('Example customer'),
            subtitle: Text('Are you available to help this afternoon?'),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('Example business reply'),
            subtitle: Text(
              _message.text.trim().isEmpty
                  ? 'Write an away message to preview it here.'
                  : _message.text.trim(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copy message'),
          onPressed: _message.text.trim().isEmpty
              ? null
              : () async {
                  await Clipboard.setData(
                    ClipboardData(text: _message.text.trim()),
                  );
                  if (context.mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Message copied. Paste it into a conversation when you choose.',
                        ),
                      ),
                    );
                },
        ),
      ],
    ),
  );
}
