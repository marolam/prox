import 'package:flutter/material.dart';

class DevUserSimulatorScreen extends StatefulWidget {
  const DevUserSimulatorScreen({super.key});
  @override
  State<DevUserSimulatorScreen> createState() => _DevUserSimulatorScreenState();
}

class _DevUserSimulatorScreenState extends State<DevUserSimulatorScreen> {
  double _radius = 2;
  bool _coffee = true;
  bool _hiking = false;
  @override
  Widget build(BuildContext context) {
    final candidates =
        [
              (name: 'Alex (example)', miles: 0.4, keyword: 'coffee'),
              (name: 'Sam (example)', miles: 1.5, keyword: 'hiking'),
              (name: 'Taylor (example)', miles: 3.2, keyword: 'coffee'),
              (name: 'Riley (example)', miles: 5.0, keyword: 'hiking'),
            ]
            .where(
              (p) =>
                  p.miles <= _radius &&
                  (p.keyword == 'coffee' ? _coffee : _hiking),
            )
            .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Discovery simulator')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'An isolated matching example. These fictional profiles never enter live discovery and no location or profile is published.',
          ),
          const SizedBox(height: 16),
          Text('Radius: ${_radius.toStringAsFixed(1)} miles'),
          Slider(
            value: _radius,
            min: 0.2,
            max: 6,
            divisions: 29,
            label: '${_radius.toStringAsFixed(1)} miles',
            onChanged: (v) => setState(() => _radius = v),
          ),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('coffee'),
                selected: _coffee,
                onSelected: (v) => setState(() => _coffee = v),
              ),
              FilterChip(
                label: const Text('hiking'),
                selected: _hiking,
                onSelected: (v) => setState(() => _hiking = v),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${candidates.length} matching examples',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No examples fit. Select a keyword or widen the radius.',
              ),
            ),
          for (final candidate in candidates)
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(candidate.name),
                subtitle: Text(
                  '${candidate.keyword} · ${candidate.miles} miles',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
