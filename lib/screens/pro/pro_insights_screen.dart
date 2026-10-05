import 'dart:async';
import 'package:flutter/material.dart';
import 'package:prox/screens/business/business_live_leads_screen.dart';
import 'package:prox/screens/settings/business_action_receipts_screen.dart';
import 'package:prox/services/business_mode/business_insights_service.dart';

class ProInsightsScreen extends StatefulWidget {
  const ProInsightsScreen({super.key, this.repository});
  final BusinessInsightsRepository? repository;

  @override
  State<ProInsightsScreen> createState() => _ProInsightsScreenState();
}

class _ProInsightsScreenState extends State<ProInsightsScreen> {
  late final BusinessInsightsRepository _repository;
  String? _uid;
  Stream<BusinessInsightsSummary>? _summary;
  StreamSubscription<String?>? _account;
  bool _accountChanged = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? BusinessInsightsService.instance;
    _uid = _repository.currentUid;
    if (_uid != null) _summary = _repository.watch(_uid!);
    _account = _repository.watchUid().listen((uid) {
      if (!mounted || uid == _uid) return;
      setState(() {
        _summary = null;
        _accountChanged = true;
      });
    });
  }

  @override
  void dispose() {
    _account?.cancel();
    super.dispose();
  }

  void _retry() {
    if (_uid == null || _repository.currentUid != _uid) return;
    setState(() => _summary = _repository.watch(_uid!));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Insights')),
    body: _accountChanged || _repository.currentUid != _uid || _uid == null
        ? const Center(child: Text('Sign in and reopen Insights to continue.'))
        : StreamBuilder<BusinessInsightsSummary>(
            stream: _summary,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Could not load your lead insights.'),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _retry,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final summary = snapshot.data;
              if (summary == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Text(
                    'Your saved leads',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (summary.leads == 0)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'No saved leads yet. Save a lead to begin tracking responses and outcomes.',
                      ),
                    ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _MetricTile(
                        label: 'Lead response',
                        value: summary.responsePercent == null
                            ? '—'
                            : '${summary.responsePercent!.round()}%',
                      ),
                      _MetricTile(
                        label: 'Deals won',
                        value: '${summary.wonLeads}',
                      ),
                      _MetricTile(
                        label: 'Median close',
                        value: _duration(summary.medianClose),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${summary.respondedLeads} of ${summary.leads} leads have a recorded response. '
                    '${summary.qualifiedLeads} are qualified.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Close-time coverage: ${summary.timedWins} of ${summary.wonLeads} wins have both creation and win timestamps.',
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.inbox_outlined),
                    title: const Text('Manage leads'),
                    subtitle: const Text('Record replies and won outcomes'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(const BusinessLiveLeadsScreen()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: const Text('Action receipts'),
                    subtitle: const Text('Actions recorded on this device'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(const BusinessActionReceiptsScreen()),
                  ),
                ],
              );
            },
          ),
  );

  void _open(Widget page) {
    if (_accountChanged || _repository.currentUid != _uid) return;
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
  }

  String _duration(Duration? duration) {
    if (duration == null) return '—';
    if (duration.inMinutes == 0) return '<1m';
    if (duration.inHours < 24) {
      return duration.inHours == 0
          ? '${duration.inMinutes}m'
          : '${duration.inHours}h ${duration.inMinutes % 60}m';
    }
    return '${duration.inDays}d ${duration.inHours % 24}h';
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: 108,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}
