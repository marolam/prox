import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:prox/services/growth_service.dart';
import 'package:prox/screens/settings/support_feedback_screen.dart';

class GrowthHubScreen extends StatefulWidget {
  const GrowthHubScreen({super.key, this.service});
  final GrowthService? service;
  @override
  State<GrowthHubScreen> createState() => _GrowthHubScreenState();
}

class _GrowthHubScreenState extends State<GrowthHubScreen> {
  late final GrowthService _service = widget.service ?? GrowthService.instance;
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _inviteLink;
  String? _inviteCode;
  String _inviteRequest = GrowthService.newRequestId();
  String _acceptRequest = GrowthService.newRequestId();
  String? _ownerUid;

  @override
  void initState() {
    super.initState();
    _ownerUid = _service.uid;
    _service.addListener(_changed);
    _service.refresh(sync: true);
  }

  void _changed() {
    if (!mounted) return;
    if (_ownerUid != _service.uid) {
      _ownerUid = _service.uid;
      _inviteLink = null;
      _inviteCode = null;
      _code.clear();
      _inviteRequest = GrowthService.newRequestId();
      _acceptRequest = GrowthService.newRequestId();
      _error = null;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Could not complete that action. Your progress is safe; please retry.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createInvite() async {
    final result = await _service.createInvite(_inviteRequest);
    if (!mounted) return;
    setState(() {
      _inviteCode = result['code']?.toString();
      _inviteLink = result['link']?.toString();
      _inviteRequest = GrowthService.newRequestId();
    });
    await _service.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final status = _service.status;
    final tester = status?.tester ?? {};
    final actions = growthMap(tester['actions']);
    final deadlineMs = tester['deadlineMs'];
    final deadline = deadlineMs is num
        ? DateTime.fromMillisecondsSinceEpoch(deadlineMs.toInt()).toLocal()
        : null;
    final expired = deadline != null && DateTime.now().isAfter(deadline);
    final referral = status?.referral ?? {};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Founding testers'),
        actions: [
          IconButton(
            onPressed: _busy
                ? null
                : () => _run(() => _service.refresh(sync: true)),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh verified progress',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _service.refresh(sync: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Three actions in your first ${status?.configInt('missionHours', 48) ?? 48} hours',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Complete your profile, exchange messages with another tester, '
              'and complete a meetup. Send all feedback through Support & feedback.',
            ),
            const SizedBox(height: 16),
            if (_service.uid == null)
              const Text('Sign in to join the tester program.')
            else if (status == null) ...[
              Text(_service.lastError ?? 'Loading your tester program…'),
              TextButton(
                onPressed: () => _service.refresh(),
                child: const Text('Retry'),
              ),
            ] else if (!status.enabled)
              const Text(
                'The tester program is currently paused. You can keep using Prox.',
              )
            else ...[
              if (!status.enrolled) ...[
                Text(
                  'Limited to ${status.configInt('testerCapacity', 20)} testers. '
                  'Join when you have time to try Prox with someone nearby.',
                ),
                const SizedBox(height: 8),
                if (tester['status'] == 'pending')
                  Text(
                    'Application received. Your ${status.configInt('missionHours', 48)}-hour mission starts when an admin approves you.',
                  )
                else
                  FilledButton(
                    onPressed: _busy ? null : () => _run(_service.join),
                    child: Text(
                      tester['status'] == 'rejected'
                          ? 'Apply again to test'
                          : 'Apply to join the tester mission',
                    ),
                  ),
              ] else ...[
                Text(
                  tester['completed'] == true
                      ? 'Mission complete — thank you for testing.'
                      : expired
                      ? 'Your mission window ended. You can still finish and report feedback.'
                      : 'Mission deadline: ${deadline?.toString().substring(0, 16) ?? 'pending'}',
                ),
                for (final action in const [
                  (
                    'profile',
                    'Save your profile',
                    'Add a name, photo, and what you seek and offer.',
                  ),
                  (
                    'chat',
                    'Have a conversation',
                    'Both testers send a message in the same chat.',
                  ),
                  (
                    'meetup',
                    'Complete a meetup',
                    'Plan, arrive, and complete it together, then rate it.',
                  ),
                ])
                  Card(
                    child: ListTile(
                      leading: Icon(
                        actions[action.$1] == true
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(action.$2),
                      subtitle: Text(action.$3),
                    ),
                  ),
                const Text(
                  'Progress updates after Prox verifies the action. Refresh if you just finished.',
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Invite a tester',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (!status.referralsEnabled)
                const Text(
                  'Referral rewards open after the first tester stage. '
                  'Existing Prox invitations remain available in Referrals.',
                )
              else ...[
                Text(
                  'Your friend gets ${status.configInt('welcomePoints', 5)} Prox points '
                  'when their invitation is accepted. You get ${status.configInt('referrerPoints', 10)} '
                  'after their profile and a real conversation or meetup are verified.',
                ),
                Text(
                  'Up to ${status.configInt('maxInvitesPerDay', 10)} invites per day; '
                  '${status.configInt('maxRewardsPerMonth', 50)} rewarded referrals and '
                  '${status.configInt('maxRewardPointsPerMonth', 100)} reward points per month. '
                  'Some rewards are held for review.',
                ),
                Text(
                  'Each link is for one new account and expires after '
                  '${status.configInt('inviteExpiryDays', 7)} days. '
                  'Accept within the account’s first seven days.',
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _run(_createInvite),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Create referral link'),
                ),
                if (_inviteCode != null) SelectableText('Code: $_inviteCode'),
                if (_inviteLink != null) ...[
                  SelectableText(_inviteLink!),
                  Center(
                    child: QrImageView(
                      data: _inviteLink!,
                      size: 180,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => _run(() async {
                          await Clipboard.setData(
                            ClipboardData(text: _inviteLink!),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Referral link copied'),
                            ),
                          );
                        }),
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy'),
                      ),
                      TextButton.icon(
                        onPressed: () => _run(() async {
                          await Share.share(_inviteLink!);
                        }),
                        icon: const Icon(Icons.share),
                        label: const Text('Share'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                if (referral.isEmpty || referral['referrerUid'] == null) ...[
                  TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Have an invitation code?',
                    ),
                    onChanged: (_) =>
                        _acceptRequest = GrowthService.newRequestId(),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await _service.acceptReferral(
                              _code.text,
                              _acceptRequest,
                            );
                            _code.clear();
                          }),
                    child: const Text('Accept invitation'),
                  ),
                ] else
                  Text(
                    'Your referral: ${referral['status'] ?? 'pending'} · '
                    'Welcome reward: ${referral['welcomeStatus'] ?? 'pending'}',
                  ),
                for (final item
                    in (status.data['invites'] as List? ?? const []))
                  Builder(
                    builder: (_) {
                      final invite = growthMap(item);
                      return ListTile(
                        title: Text(invite['code']?.toString() ?? 'Invitation'),
                        subtitle: Text(
                          invite['status']?.toString() ??
                              (invite['claimed'] == true
                                  ? 'Accepted'
                                  : 'Awaiting acceptance'),
                        ),
                      );
                    },
                  ),
              ],
            ],
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SupportFeedbackScreen(),
                ),
              ),
              icon: const Icon(Icons.support_agent),
              label: const Text('Support & feedback'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!),
              ),
          ],
        ),
      ),
    );
  }
}

class GrowthReferralEntry extends StatelessWidget {
  const GrowthReferralEntry({super.key});
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.groups_outlined),
      title: const Text('Founding tester rewards'),
      subtitle: const Text(
        '48-hour mission, referral links, and verified rewards.',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const GrowthHubScreen())),
    ),
  );
}
