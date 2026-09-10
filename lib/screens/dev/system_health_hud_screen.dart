import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:prox/services/app_build_info_service.dart';
import 'package:prox/services/runtime_diagnostics_service.dart';

class SystemHealthHudScreen extends StatefulWidget {
  const SystemHealthHudScreen({super.key});
  @override
  State<SystemHealthHudScreen> createState() => _SystemHealthHudScreenState();
}

class _SystemHealthHudScreenState extends State<SystemHealthHudScreen> {
  Map<String, String> _checks = {};
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final checks = <String, String>{
      'Platform': kIsWeb ? 'Web' : defaultTargetPlatform.name,
    };
    try {
      checks['App version'] = await AppBuildInfoService.instance.fullVersion();
    } catch (_) {
      checks['App version'] = 'Unavailable';
    }
    try {
      final connections = await Connectivity().checkConnectivity().timeout(
        const Duration(seconds: 5),
      );
      checks['Network interface'] = connections.map((v) => v.name).join(', ');
    } catch (_) {
      checks['Network interface'] = 'Unavailable';
    }
    try {
      checks['Location services'] =
          await Geolocator.isLocationServiceEnabled().timeout(
            const Duration(seconds: 5),
          )
          ? 'Enabled'
          : 'Disabled';
      checks['Location permission'] =
          (await Geolocator.checkPermission().timeout(
            const Duration(seconds: 5),
          )).name;
    } catch (_) {
      checks['Location permission'] = 'Unavailable on this device';
    }
    try {
      checks['Account'] = FirebaseAuth.instance.currentUser == null
          ? 'Signed out'
          : 'Signed in';
    } catch (_) {
      checks['Account'] = 'Unavailable';
    }
    if (mounted)
      setState(() {
        _checks = checks;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('System health'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _refresh,
          tooltip: 'Refresh checks',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: RuntimeDiagnosticsService.instance,
      builder: (context, _) {
        final issues = RuntimeDiagnosticsService.instance.issues;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Read-only checks from this device. A connected network interface does not guarantee internet access.',
            ),
            if (_loading)
              const LinearProgressIndicator(
                semanticsLabel: 'Checking device status',
              ),
            for (final entry in _checks.entries)
              ListTile(title: Text(entry.key), subtitle: Text(entry.value)),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy diagnostic summary'),
              onPressed: _loading
                  ? null
                  : () async {
                      final summary = [
                        'Prox device checks',
                        ..._checks.entries.map((e) => '${e.key}: ${e.value}'),
                        'Recent local issues: ${issues.length}',
                        ...issues.map(
                          (i) =>
                              '${i.occurredAt.toIso8601String()} | ${i.operation} | ${i.kind}',
                        ),
                      ].join('\n');
                      await Clipboard.setData(ClipboardData(text: summary));
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Summary copied. You can include it in a support report.',
                            ),
                          ),
                        );
                    },
            ),
            const Divider(height: 32),
            Text(
              'Recent local issues',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Only operation names and error types are listed. This session history is limited to 50 records.',
            ),
            if (issues.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No issues recorded in this session.'),
              ),
            for (final issue in issues)
              ListTile(
                leading: Icon(
                  issue.fatal ? Icons.error_outline : Icons.info_outline,
                ),
                title: Text(issue.operation),
                subtitle: Text('${issue.kind} · ${issue.occurredAt.toLocal()}'),
              ),
          ],
        );
      },
    ),
  );
}
