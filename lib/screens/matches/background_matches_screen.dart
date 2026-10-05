import 'dart:async';
import 'package:flutter/material.dart';
import 'package:prox/screens/matches/significant_match_screen.dart';
import 'package:prox/services/background_opportunity_service.dart';

/// A bounded snapshot, fetched on opening or explicit refresh; no background listener.
class BackgroundMatchesScreen extends StatefulWidget {
  const BackgroundMatchesScreen({super.key, this.service});
  final BackgroundOpportunityService? service;
  @override
  State<BackgroundMatchesScreen> createState() =>
      _BackgroundMatchesScreenState();
}

class _BackgroundMatchesScreenState extends State<BackgroundMatchesScreen> {
  late final BackgroundOpportunityService _service;
  late final String? _accountUid;
  late Future<List<Map<String, dynamic>>> _matches;
  StreamSubscription<String?>? _accountSubscription;
  bool _accountChanged = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? BackgroundOpportunityService.instance;
    _accountUid = _service.currentUid;
    _matches = _load();
    _accountSubscription = _service.accountChanges.listen((uid) {
      if (!mounted || uid == _accountUid) return;
      setState(() {
        _accountChanged = true;
        _matches = Future.value([]);
      });
      if (ModalRoute.of(context)?.isCurrent == true) {
        unawaited(Navigator.of(context).maybePop());
      }
    });
  }

  Future<List<Map<String, dynamic>>> _load() =>
      _service.list(_accountUid ?? '');

  @override
  void dispose() {
    unawaited(_accountSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Background matches'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: _accountChanged || _service.currentUid != _accountUid
              ? null
              : () => setState(() => _matches = _load()),
        ),
      ],
    ),
    body: _accountChanged || _service.currentUid != _accountUid
        ? const Center(child: Text('Return to Nearby to continue.'))
        : FutureBuilder<List<Map<String, dynamic>>>(
            future: _matches,
            builder: (context, snapshot) {
              if (_accountChanged || _service.currentUid != _accountUid) {
                return const Center(
                  child: Text('Return to Nearby to continue.'),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting)
                return const Center(child: CircularProgressIndicator());
              if (snapshot.hasError)
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Could not check background matches. Check your connection and refresh.',
                    ),
                  ),
                );
              final matches = snapshot.data ?? [];
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'Recent connections found quietly. Only significant matches can alert you. Availability can change.',
                  ),
                  const SizedBox(height: 16),
                  if (matches.isEmpty)
                    const Text(
                      'No current background matches. Enable background matching in Sound & alerts to keep looking while Prox is closed.',
                    ),
                  for (final match in matches)
                    ListTile(
                      leading: Icon(
                        match['significant'] == true
                            ? Icons.auto_awesome
                            : Icons.people_outline,
                      ),
                      title: Text(match['displayName'] as String),
                      subtitle: Text(
                        match['significant'] == true
                            ? 'Multiple keywords match both ways'
                            : 'A possible connection',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SignificantMatchScreen(
                            opportunityId: match['opportunityId'] as String,
                            service: _service,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
  );
}
