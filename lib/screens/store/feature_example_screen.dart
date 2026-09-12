import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Offline product examples never call purchase or entitlement services.
class FeatureExampleScreen extends StatefulWidget {
  const FeatureExampleScreen({super.key, this.title = 'Pro tools example'});
  final String title;
  @override
  State<FeatureExampleScreen> createState() => _FeatureExampleScreenState();
}

class _FeatureExampleScreenState extends State<FeatureExampleScreen> {
  double _radius = 5;
  double _discount = 15;
  bool _availableOnly = false;
  String _reply =
      'Thanks for your interest! Tell me what you need and when you are available.';
  final Set<String> _saved = {};
  static const _leads = [
    (
      name: 'Example: Jordan',
      need: 'Bike tune-up',
      miles: 1.2,
      available: true,
    ),
    (
      name: 'Example: Morgan',
      need: 'Weekend repair',
      miles: 3.8,
      available: false,
    ),
    (
      name: 'Example: Casey',
      need: 'Equipment advice',
      miles: 8.5,
      available: true,
    ),
  ];
  @override
  Widget build(BuildContext context) {
    final leads = _leads
        .where((l) => l.miles <= _radius && (!_availableOnly || l.available))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'INTERACTIVE EXAMPLE\nAll people, prices, and results on this page are illustrative. Changes stay on this page. No points are spent, no messages are sent, and no paid access is granted.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Find the right request',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('Example service area: ${_radius.round()} miles'),
          Slider(
            value: _radius,
            min: 1,
            max: 15,
            divisions: 14,
            label: '${_radius.round()} miles',
            onChanged: (v) => setState(() => _radius = v),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show available examples only'),
            value: _availableOnly,
            onChanged: (v) => setState(() => _availableOnly = v),
          ),
          if (leads.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No example requests fit these filters. Increase the radius or turn off available-only.',
              ),
            ),
          for (final lead in leads)
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(lead.name),
                subtitle: Text(
                  '${lead.need} · ${lead.miles} mi · ${lead.available ? 'Available' : 'Later'}',
                ),
                trailing: IconButton(
                  tooltip: _saved.contains(lead.name)
                      ? 'Unsave example'
                      : 'Save example',
                  icon: Icon(
                    _saved.contains(lead.name)
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                  ),
                  onPressed: () => setState(() {
                    _saved.contains(lead.name)
                        ? _saved.remove(lead.name)
                        : _saved.add(lead.name);
                  }),
                ),
              ),
            ),
          Text('${_saved.length} examples saved on this page'),
          const Divider(height: 32),
          Text(
            'Plan a promotion',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text('Use a sample price of 100 units to explore a discount.'),
          Slider(
            value: _discount,
            min: 0,
            max: 50,
            divisions: 10,
            label: '${_discount.round()}% off',
            onChanged: (v) => setState(() => _discount = v),
          ),
          Text(
            'Example: ${_discount.round()}% off · ${(100 - _discount).toStringAsFixed(0)} units after discount',
          ),
          const Divider(height: 32),
          Text(
            'Try a reply template',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('Welcome'),
                onPressed: () => setState(
                  () => _reply =
                      'Thanks for your interest! Tell me what you need and when you are available.',
                ),
              ),
              ActionChip(
                label: const Text('Away'),
                onPressed: () => setState(
                  () => _reply =
                      'Thanks for reaching out. I am away right now and will respond when available.',
                ),
              ),
              ActionChip(
                label: const Text('Follow up'),
                onPressed: () => setState(
                  () => _reply =
                      'Checking in: do you still need help? Let me know if your plans have changed.',
                ),
              ),
            ],
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(_reply),
            ),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy example reply'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _reply));
              if (context.mounted)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Example reply copied.')),
                );
            },
          ),
          const SizedBox(height: 12),
          const ExpansionTile(
            title: Text('Example action receipt'),
            leading: Icon(Icons.receipt_long_outlined),
            childrenPadding: EdgeInsets.all(16),
            children: [
              Text(
                'Action: save a reply template\nStatus: example only\nCharge: none\nLive receipts should identify the confirmed action and time. A payment or activation must be verified before showing success.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
