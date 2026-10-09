import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:prox/services/growth_service.dart';
import 'package:prox/widgets/support_attachment_preview.dart';
import 'package:prox/screens/support/support_ticket_screen.dart';
import 'package:prox/utils/dialog_lifecycle.dart';
import 'package:prox/widgets/account_moderation_panel.dart';

class GrowthOpsEntry extends StatelessWidget {
  const GrowthOpsEntry({super.key});
  Future<bool> _authorized() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdTokenResult();
      return token?.claims?['admin'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _authorized(),
    builder: (context, snapshot) => snapshot.data == true
        ? Card(
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Tester operations'),
              subtitle: const Text(
                'Support, rewards, rollout, and daily metrics.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const GrowthOpsScreen(),
                ),
              ),
            ),
          )
        : const SizedBox.shrink(),
  );
}

class GrowthOpsScreen extends StatefulWidget {
  const GrowthOpsScreen({super.key, this.service});
  final GrowthService? service;
  @override
  State<GrowthOpsScreen> createState() => _GrowthOpsScreenState();
}

class _GrowthOpsScreenState extends State<GrowthOpsScreen> {
  late final GrowthService _service = widget.service ?? GrowthService.instance;
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  String? _legacyCursor;
  String? _legacyImportMessage;
  late final String? _ownerUid = _service.uid;
  @override
  void initState() {
    super.initState();
    _service.addListener(_accountChanged);
    _load();
  }

  void _accountChanged() {
    if (!mounted || _ownerUid == _service.uid) return;
    setState(() {
      _data = null;
      _legacyCursor = null;
      _legacyImportMessage = null;
      _error =
          'Account changed. Reopen operations from the signed-in admin account.';
    });
    final route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && route != null)
        Navigator.of(context).popUntil((candidate) => candidate == route);
    });
  }

  @override
  void dispose() {
    _service.removeListener(_accountChanged);
    super.dispose();
  }

  Future<void> _load() => _run(() async {
    final result = await _service.call('getGrowthOps', {'days': 14});
    if (mounted) setState(() => _data = result);
  });
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    if (_ownerUid != _service.uid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (error is FirebaseFunctionsException &&
          const ['permission-denied', 'unauthenticated'].contains(error.code)) {
        _data = null;
        _legacyCursor = null;
        _legacyImportMessage = null;
      }
      if (mounted)
        setState(
          () => _error = error is FirebaseFunctionsException
              ? error.message ?? 'Operations request failed.'
              : 'Operations request failed. Please retry.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editConfig() async {
    final config = growthMap(_data?['config']);
    var enabled = config['enabled'] == true;
    var stage = config['stage']?.toString() ?? 'testers';
    final fields = <String, TextEditingController>{
      for (final entry in const {
        'testerCapacity': 20,
        'missionHours': 48,
        'welcomePoints': 5,
        'referrerPoints': 10,
        'maxInvitesPerDay': 10,
        'maxRewardsPerMonth': 50,
        'maxRewardPointsPerMonth': 100,
        'holdHours': 24,
      }.entries)
        entry.key: TextEditingController(
          text: (config[entry.key] ?? entry.value).toString(),
        ),
    };
    final labels = {
      'testerCapacity': 'Tester capacity (10–20)',
      'missionHours': 'Tester mission hours (24–168)',
      'welcomePoints': 'Welcome points',
      'referrerPoints': 'Points per qualified referral',
      'maxInvitesPerDay': 'Invites per person per day',
      'maxRewardsPerMonth': 'Rewarded referrals per person per month',
      'maxRewardPointsPerMonth': 'Maximum referral reward points per month',
      'holdHours': 'Minimum review hold in hours',
    };
    Map<String, dynamic>? patch;
    await showDialogUntilRemoved<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Tester rollout and rewards'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Enable tester program'),
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: stage,
                    decoration: const InputDecoration(
                      labelText: 'Rollout stage',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'testers',
                        child: Text('1. Tester mission'),
                      ),
                      DropdownMenuItem(
                        value: 'referrals',
                        child: Text('2. Referral rewards'),
                      ),
                      DropdownMenuItem(
                        value: 'support',
                        child: Text('3. Support operations'),
                      ),
                    ],
                    onChanged: (value) => stage = value ?? stage,
                  ),
                  for (final entry in fields.entries)
                    TextField(
                      controller: entry.value,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: labels[entry.key]),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Existing earned points remain in the wallet. '
                    'New rules apply to new invitations.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final values = {
                  for (final entry in fields.entries)
                    entry.key: int.tryParse(entry.value.text),
                };
                if (values.values.any((value) => value == null)) return;
                patch = {
                  ...config,
                  ...values,
                  'enabled': enabled,
                  'stage': stage,
                };
                Navigator.pop(dialogContext);
              },
              child: const Text('Save rules'),
            ),
          ],
        ),
      ),
    );
    for (final field in fields.values) {
      field.dispose();
    }
    if (patch == null || !mounted) return;
    await _run(() async {
      await _service.call('updateGrowthConfig', {'config': patch});
    });
    if (mounted && _error == null) await _load();
  }

  Future<void> _editFollowups() => _run(() async {
    final config = await _service.call('configureBusinessAutomation');
    if (!mounted || _ownerUid != _service.uid) return;
    var enabled = config['enabled'] == true;
    var outbound = config['outboundEnabled'] == true;
    var idempotent = config['providerIdempotency'] == true;
    final providers = growthMap(config['providersConfigured']);
    final deliveryAvailable =
        config['outboundDeploymentEnabled'] == true &&
        (providers['sms'] == true || providers['email'] == true);
    final save = await showDialogUntilRemoved<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Business follow-ups'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Owner follow-up reminders'),
                  subtitle: const Text(
                    'Show due reminders and suggested replies in Business Live Leads.',
                  ),
                  value: enabled,
                  onChanged: (value) => update(() => enabled = value),
                ),
                SwitchListTile(
                  title: const Text('Customer delivery'),
                  subtitle: Text(
                    deliveryAvailable
                        ? 'Only recipients with recorded consent are eligible.'
                        : 'Delivery is awaiting provider setup. Owner reminders can run separately.',
                  ),
                  value: outbound,
                  onChanged: deliveryAvailable
                      ? (value) => update(() => outbound = value)
                      : null,
                ),
                if (deliveryAvailable)
                  CheckboxListTile(
                    title: const Text('Provider prevents duplicate delivery'),
                    subtitle: const Text(
                      'Confirm that repeated delivery IDs produce one message.',
                    ),
                    value: idempotent,
                    onChanged: (value) =>
                        update(() => idempotent = value == true),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: outbound && !idempotent
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (save != true) return;
    await _service.call('configureBusinessAutomation', {
      'enabled': enabled,
      'outboundEnabled': outbound,
      'providerIdempotency': idempotent,
    });
  });

  Future<void> _triage(Map<String, dynamic> ticket) async {
    var category = ticket['category']?.toString() ?? 'bug';
    var severity = ticket['severity']?.toString() ?? 'P2';
    var status = ticket['status']?.toString() ?? 'open';
    final reply = TextEditingController();
    final version = TextEditingController(
      text: ticket['fixedVersion']?.toString() ?? '',
    );
    final build = TextEditingController(
      text: ticket['fixedBuild']?.toString() ?? '',
    );
    final requestId = GrowthService.newRequestId();
    String? saveError;
    bool saving = false;
    await showDialogUntilRemoved<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text(ticket['subject']?.toString() ?? 'Support report'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ticket['message']?.toString() ?? ''),
                  const SizedBox(height: 8),
                  Text(
                    'Reporter: ${ticket['uid'] ?? ticket['ownerUid'] ?? 'unknown'}',
                  ),
                  Text('Metadata: ${growthMap(ticket['metadata'])}'),
                  for (final path in (ticket['attachmentPaths'] as List? ?? []))
                    SupportAttachmentPreview(path: path.toString()),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SupportTicketScreen.forTicketId(
                          ticketId: ticket['id'].toString(),
                        ),
                      ),
                    ),
                    child: const Text('View full conversation'),
                  ),
                  const Text('P0: hotfix · P1: next patch · P2: weekly batch'),
                  for (final item in [
                    (
                      'Category',
                      category,
                      const ['bug', 'ux', 'billing', 'feature', 'question'],
                    ),
                    ('Severity', severity, const ['P0', 'P1', 'P2']),
                    (
                      'Status',
                      status,
                      const [
                        'open',
                        'acknowledged',
                        'in_progress',
                        'resolved',
                        'closed',
                      ],
                    ),
                  ])
                    DropdownButtonFormField<String>(
                      initialValue: item.$3.contains(item.$2)
                          ? item.$2
                          : item.$3.first,
                      decoration: InputDecoration(labelText: item.$1),
                      items: item.$3
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: saving
                          ? null
                          : (value) {
                              if (item.$1 == 'Category') category = value!;
                              if (item.$1 == 'Severity') severity = value!;
                              if (item.$1 == 'Status') status = value!;
                            },
                    ),
                  TextField(
                    controller: reply,
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Reply to reporter',
                    ),
                  ),
                  TextField(
                    controller: version,
                    decoration: const InputDecoration(
                      labelText: 'Fixed in version (for bug resolution)',
                    ),
                  ),
                  TextField(
                    controller: build,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Fixed in build number',
                    ),
                  ),
                  if (saveError != null) Text(saveError!),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() {
                        saving = true;
                        saveError = null;
                      });
                      try {
                        await _service.call('updateSupportTicket', {
                          'ticketId': ticket['id'],
                          'requestId': requestId,
                          'category': category,
                          'severity': severity,
                          'status': status,
                          'reply': reply.text.trim(),
                          'fixedVersion': version.text.trim(),
                          'fixedBuild': build.text.trim(),
                        });
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (error) {
                        if (dialogContext.mounted)
                          setDialogState(() {
                            saving = false;
                            saveError = error is FirebaseFunctionsException
                                ? error.message
                                : 'Could not save. Retry.';
                          });
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save and notify'),
            ),
          ],
        ),
      ),
    );
    reply.dispose();
    version.dispose();
    build.dispose();
    if (mounted) await _load();
  }

  Future<void> _review(Map<String, dynamic> reward, String decision) async {
    final note = TextEditingController();
    final accepted = await showDialogUntilRemoved<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          decision == 'release' ? 'Release held reward' : 'Reject held reward',
        ),
        content: TextField(
          controller: note,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason for this decision',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (note.text.trim().isNotEmpty)
                Navigator.pop(dialogContext, true);
            },
            child: const Text('Apply decision'),
          ),
        ],
      ),
    );
    final reason = note.text.trim();
    note.dispose();
    if (accepted != true || !mounted) return;
    await _run(() async {
      await _service.call('reviewGrowthReward', {
        'inviteeUid': reward['inviteeUid'] ?? reward['uid'],
        'decision': decision,
        'note': reason,
      });
    });
    if (mounted && _error == null) await _load();
  }

  Future<void> _reviewTester(
    Map<String, dynamic> application,
    String decision,
  ) async {
    await _run(() async {
      await _service.call('reviewTesterApplication', {
        'uid': application['uid'],
        'decision': decision,
        'note': decision == 'approve'
            ? 'Selected for founding tester cohort'
            : 'Not selected for current cohort',
      });
    });
    if (mounted && _error == null) await _load();
  }

  Future<void> _importLegacy() async {
    await _run(() async {
      final result = await _service.call('backfillLegacySupport', {
        'limit': 100,
        if (_legacyCursor != null) 'cursor': _legacyCursor,
      });
      if (!mounted) return;
      setState(() {
        _legacyCursor = result['nextCursor']?.toString();
        _legacyImportMessage = result['done'] == true
            ? 'Existing reports are available in the support queue.'
            : '${result['processed'] ?? 0} older records checked. Load the next batch to continue.';
      });
    });
    if (mounted && _error == null) await _load();
  }

  String _percent(dynamic value) =>
      value is num ? '${(value * 100).toStringAsFixed(1)}%' : 'Awaiting data';
  String _minutes(dynamic value) =>
      value is num ? '${value.toStringAsFixed(1)} min' : 'Awaiting a response';
  List<Map<String, dynamic>> _rows(String field) =>
      (_data?[field] as List? ?? []).map(growthMap).toList();

  Widget _metricCard(BuildContext context, Map<String, dynamic> metric) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric['day']?.toString() ?? 'Day',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            'Activation in 24h: ${_percent(metric['activationRate'])} '
            '(${metric['activatedWithin24h'] ?? 0}/${metric['activationEligible'] ?? 0} eligible)',
          ),
          Text(
            'Referral conversion (created invites): ${_percent(metric['referralConversion'])} '
            '(${metric['referredActivated'] ?? 0}/${metric['invitesSent'] ?? 0})',
          ),
          Text(
            'Day 1: ${_percent(metric['day1Retention'])} · Day 7: ${_percent(metric['day7Retention'])}',
          ),
          Text(
            'Median first response: ${_minutes(metric['medianFirstResponseMinutes'])}',
          ),
          Text(
            'Reported crash-free sessions: ${_percent(metric['crashFreeSessions'])}',
          ),
          Text(
            'Top errors: ${(metric['topErrors'] as List? ?? []).map((e) {
              final row = growthMap(e);
              return '${row['source']}: ${row['count']}';
            }).join(', ')}',
          ),
          if (growthMap(metric['coverage'])['truncated'] == true)
            const Text(
              'This view is sampled. Export full data before making rollout decisions.',
            ),
        ],
      ),
    ),
  );

  List<Widget> _metricCards(BuildContext context) {
    final metrics = _rows('metrics')
      ..sort(
        (a, b) =>
            (b['day']?.toString() ?? '').compareTo(a['day']?.toString() ?? ''),
      );
    return [
      if (metrics.isNotEmpty) _metricCard(context, metrics.first),
      if (metrics.length > 1)
        ExpansionTile(
          title: const Text('Previous daily metrics'),
          children: [
            for (final metric in metrics.skip(1)) _metricCard(context, metric),
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Tester operations'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ...[
          Text(_error!),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
        if (_data != null) ...[
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Account moderation'),
            subtitle: const Text(
              'Suspend, restore or permanently delete an abusive account.',
            ),
            onTap: _busy || _ownerUid == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          AccountModerationPanel(ownerUid: _ownerUid),
                    ),
                  ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Rollout controls'),
            subtitle: Text(
              'Stage: ${growthMap(_data!['config'])['stage']} · '
              '${growthMap(_data!['config'])['enabled'] == true ? 'Enabled' : 'Paused'}',
            ),
            trailing: OutlinedButton(
              onPressed: _busy ? null : _editConfig,
              child: const Text('Configure'),
            ),
          ),
          ListTile(
            title: const Text('Business follow-ups'),
            subtitle: const Text(
              'Owner reminders and configured customer delivery',
            ),
            trailing: OutlinedButton(
              onPressed: _busy ? null : _editFollowups,
              child: const Text('Configure'),
            ),
          ),
          Text('Daily metrics', style: Theme.of(context).textTheme.titleLarge),
          const Text(
            'Retention waits for cohorts to mature. Crash coverage includes '
            'opted-in sessions and reported fatal errors; Crashlytics remains the crash authority.',
          ),
          ..._metricCards(context),
          const SizedBox(height: 16),
          Text('Support queue', style: Theme.of(context).textTheme.titleLarge),
          TextButton.icon(
            onPressed: _busy ? null : _importLegacy,
            icon: const Icon(Icons.history),
            label: Text(
              _legacyCursor == null
                  ? 'Load existing reports'
                  : 'Load next batch of existing reports',
            ),
          ),
          if (_legacyImportMessage != null) Text(_legacyImportMessage!),
          const Text(
            'Acknowledge today. P0: hotfix · P1: next patch · P2: weekly batch.',
          ),
          if (_rows('tickets').isEmpty) const Text('No support reports yet.'),
          for (final ticket in _rows('tickets'))
            Card(
              child: ListTile(
                title: Text(
                  '${ticket['severity'] ?? 'P2'} · ${ticket['subject'] ?? 'Report'}',
                ),
                subtitle: Text('${ticket['category']} · ${ticket['status']}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : () => _triage(ticket),
              ),
            ),
          const SizedBox(height: 16),
          Text('Held rewards', style: Theme.of(context).textTheme.titleLarge),
          if (_rows('heldRewards').isEmpty)
            const Text('No rewards awaiting review.'),
          for (final reward in _rows('heldRewards'))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reward['inviteeUid']?.toString() ??
                          reward['uid']?.toString() ??
                          '',
                    ),
                    Text((reward['reasons'] as List? ?? []).join(', ')),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _review(reward, 'release'),
                          child: const Text('Release'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _review(reward, 'reject'),
                          child: const Text('Reject'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Tester applications',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Choose people who can test together. Approval starts their mission clock.',
          ),
          if (_rows('applications').isEmpty)
            const Text('No tester applications awaiting a decision.'),
          for (final application in _rows('applications'))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      application['displayName']?.toString() ??
                          application['uid']?.toString() ??
                          'Applicant',
                    ),
                    Text(application['uid']?.toString() ?? ''),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _reviewTester(application, 'approve'),
                          child: const Text('Approve'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _reviewTester(application, 'reject'),
                          child: const Text('Decline'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Tester cohort (${_rows('testers').length})',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final tester in _rows('testers'))
            ListTile(
              title: Text(tester['uid']?.toString() ?? ''),
              subtitle: Text(
                tester['completed'] == true
                    ? 'Mission complete'
                    : 'Mission in progress',
              ),
            ),
        ],
      ],
    ),
  );
}
