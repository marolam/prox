import 'package:flutter/material.dart';
import 'package:prox/services/user_settings_service.dart';

class CosmeticsScreen extends StatefulWidget {
  const CosmeticsScreen({super.key});
  @override
  State<CosmeticsScreen> createState() => _CosmeticsScreenState();
}

class _CosmeticsScreenState extends State<CosmeticsScreen> {
  Color _color = Colors.teal;
  bool _frame = true;
  @override
  Widget build(BuildContext context) {
    final service = UserSettingsService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Cosmetics & readability')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Readability', style: Theme.of(context).textTheme.titleLarge),
          StreamBuilder(
            stream: service.watch(),
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'App text size: ${(service.current.textScaleFactor * 100).round()}%',
                ),
                Slider(
                  value: service.current.textScaleFactor,
                  min: 0.9,
                  max: 1.6,
                  divisions: 7,
                  label: '${(service.current.textScaleFactor * 100).round()}%',
                  semanticFormatterCallback: (v) =>
                      '${(v * 100).round()} percent',
                  onChanged: service.setTextScaleFactor,
                ),
                TextButton(
                  onPressed: () => service.setTextScaleFactor(1),
                  child: const Text('Reset app text size'),
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          Text(
            'Style playground',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'A local example of profile flair. Changes here only affect this preview; they do not purchase cosmetics or change your live profile.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in const [
                (name: 'Ocean', color: Colors.teal),
                (name: 'Sunset', color: Colors.deepOrange),
                (name: 'Violet', color: Colors.deepPurple),
              ])
                ChoiceChip(
                  label: Text(choice.name),
                  selected: _color == choice.color,
                  onSelected: (_) => setState(() => _color = choice.color),
                ),
            ],
          ),
          SwitchListTile.adaptive(
            title: const Text('Show profile frame'),
            value: _frame,
            onChanged: (v) => setState(() => _frame = v),
          ),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: _frame
                  ? BorderSide(color: _color, width: 3)
                  : BorderSide.none,
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  CircleAvatar(
                    backgroundColor: _color,
                    foregroundColor: Colors.white,
                    radius: 32,
                    child: const Icon(Icons.person_outline, size: 36),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Example profile',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text('Looking For: a coffee conversation'),
                  const Text('Can Provide: local recommendations'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
