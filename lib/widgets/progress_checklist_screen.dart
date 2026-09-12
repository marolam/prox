import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A local, resumable manual checklist. Checks are observations, not test results.
class ProgressChecklistScreen extends StatefulWidget {
  const ProgressChecklistScreen({
    super.key,
    required this.title,
    required this.storageKey,
    required this.introduction,
    required this.steps,
  });

  final String title;
  final String storageKey;
  final String introduction;
  final List<({String title, String detail})> steps;

  @override
  State<ProgressChecklistScreen> createState() =>
      _ProgressChecklistScreenState();
}

class _ProgressChecklistScreenState extends State<ProgressChecklistScreen> {
  final Set<String> _checked = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved =
          prefs.getStringList('checklist.v1.${widget.storageKey}') ?? [];
      if (!mounted) return;
      setState(() {
        _checked
          ..clear()
          ..addAll(
            saved.where((title) => widget.steps.any((s) => s.title == title)),
          );
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = 'Could not load your checklist. Try again.';
        });
    }
  }

  Future<void> _save(Set<String> next) async {
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setStringList(
        'checklist.v1.${widget.storageKey}',
        next.toList(),
      );
      if (!saved) throw StateError('Storage unavailable');
      if (!mounted) return;
      setState(() {
        _checked
          ..clear()
          ..addAll(next);
        _error = null;
      });
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not save this change. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(widget.introduction),
                const SizedBox(height: 12),
                const Text(
                  'Progress is saved on this device. Mark a step only after you have tried it.',
                ),
                const SizedBox(height: 16),
                Text(
                  '${_checked.length} of ${widget.steps.length} completed',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: widget.steps.isEmpty
                      ? 0
                      : _checked.length / widget.steps.length,
                  semanticsLabel: 'Checklist progress',
                ),
                if (_error != null)
                  ListTile(
                    title: Text(_error!),
                    trailing: TextButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ),
                const SizedBox(height: 12),
                for (final step in widget.steps)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _checked.contains(step.title),
                    title: Text(step.title),
                    subtitle: Text(step.detail),
                    onChanged: _saving
                        ? null
                        : (value) {
                            final next = {..._checked};
                            value == true
                                ? next.add(step.title)
                                : next.remove(step.title);
                            _save(next);
                          },
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Copy progress'),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text:
                                '${widget.title}\nManual checklist, ${DateTime.now().toIso8601String()}\n${widget.steps.map((s) => '${_checked.contains(s.title) ? '[x]' : '[ ]'} ${s.title}').join('\n')}',
                          ),
                        );
                        if (context.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Checklist copied.')),
                          );
                      },
                    ),
                    TextButton(
                      onPressed: _saving || _checked.isEmpty
                          ? null
                          : () => _save({}),
                      child: const Text('Reset progress'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
