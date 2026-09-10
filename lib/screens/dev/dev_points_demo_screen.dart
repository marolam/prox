import 'package:flutter/material.dart';

class DevPointsDemoScreen extends StatefulWidget {
  static const String routeName = '/dev/points-demo';
  const DevPointsDemoScreen({super.key});
  @override
  State<DevPointsDemoScreen> createState() => _DevPointsDemoScreenState();
}

class _DevPointsDemoScreenState extends State<DevPointsDemoScreen> {
  int _points = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Points example')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'A local points counter for practicing the interface. These example points are not spendable and never change your account balance or trust.',
        ),
        const SizedBox(height: 24),
        Semantics(
          liveRegion: true,
          child: Text(
            '$_points example points',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final amount in [5, 25, 100])
              OutlinedButton(
                onPressed: () => setState(() => _points += amount),
                child: Text('Add $amount examples'),
              ),
            FilledButton(
              onPressed: _points < 25
                  ? null
                  : () => setState(() => _points -= 25),
              child: const Text('Spend 25 examples'),
            ),
            TextButton(
              onPressed: () => setState(() => _points = 0),
              child: const Text('Reset example'),
            ),
          ],
        ),
      ],
    ),
  );
}
