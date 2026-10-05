import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prox/services/chat/chat_thread_service.dart';
import 'package:prox/services/meetup_service.dart';
import 'package:prox/widgets/prox_circle_hold.dart';
import 'package:prox/services/matching/matching_mode_service.dart';
import 'package:prox/services/background_opportunity_service.dart';

class SignificantMatchScreen extends StatefulWidget {
  const SignificantMatchScreen({
    super.key,
    required this.opportunityId,
    this.service,
  });
  final String opportunityId;
  final BackgroundOpportunityService? service;
  @override
  State<SignificantMatchScreen> createState() => _SignificantMatchScreenState();
}

class _SignificantMatchScreenState extends State<SignificantMatchScreen> {
  double _progress = 0;
  bool _opening = false;
  late final BackgroundOpportunityService _service;
  late final String? _accountUid;
  late Future<Map<String, dynamic>> _opportunity;
  StreamSubscription<String?>? _accountSubscription;
  bool _accountChanged = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? BackgroundOpportunityService.instance;
    _accountUid = _service.currentUid;
    _opportunity = _load();
    _accountSubscription = _service.accountChanges.listen((uid) {
      if (!mounted || uid == _accountUid) return;
      setState(() {
        _accountChanged = true;
        _opportunity = Future.value({'available': false});
        _progress = 0;
        _opening = false;
      });
      if (ModalRoute.of(context)?.isCurrent == true) {
        unawaited(Navigator.of(context).maybePop());
      }
    });
  }

  @override
  void dispose() {
    unawaited(_accountSubscription?.cancel());
    super.dispose();
  }

  Future<void> _openConnection() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid != _accountUid || _accountChanged) {
        throw StateError('Sign in to continue.');
      }
      final fresh = await _load();
      if (!mounted ||
          FirebaseAuth.instance.currentUser?.uid != uid ||
          fresh['available'] != true)
        throw StateError('This opportunity has changed.');
      final other = fresh['otherUid'] as String;
      final thread = ChatThreadService.instance.chatIdFor(uid, other);
      final cooldown = await MeetupService.instance.declineCooldownLeft(thread);
      if (cooldown != null && cooldown > Duration.zero)
        throw StateError('This connection is temporarily on cooldown.');
      if (!mounted ||
          FirebaseAuth.instance.currentUser?.uid != uid ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
          MatchingModeService.instance.modeKind.name != fresh['modeKind'])
        return;
      if (fresh['modeKind'] == 'normal' &&
          MatchingModeService.instance.isActiveLocked)
        throw StateError('Active matching is temporarily locked.');
      if (fresh['modeKind'] == 'normal')
        MatchingModeService.instance.setMode(ProxMatchingMode.active);
      final chatId = await ChatThreadService.instance.ensureChat(
        myUid: uid,
        otherUid: other,
      );
      if (mounted && FirebaseAuth.instance.currentUser?.uid == uid)
        Navigator.of(
          context,
        ).pushNamed('/chat', arguments: {'chatId': chatId, 'otherUid': other});
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This connection is unavailable or Active is temporarily locked. Please try Nearby.',
            ),
          ),
        );
    } finally {
      if (mounted)
        setState(() {
          _opening = false;
          _progress = 0;
        });
    }
  }

  Future<Map<String, dynamic>> _load() =>
      _service.get(_accountUid ?? '', widget.opportunityId);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Background connection')),
    body: _accountChanged || _service.currentUid != _accountUid
        ? const Center(child: Text('Return to Nearby to continue.'))
        : FutureBuilder<Map<String, dynamic>>(
            future: _opportunity,
            builder: (context, snapshot) {
              if (_accountChanged || _service.currentUid != _accountUid) {
                return const Center(
                  child: Text('Return to Nearby to continue.'),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting)
                return const Center(child: CircularProgressIndicator());
              final data = snapshot.data;
              if (snapshot.hasError || data?['available'] != true)
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'This opportunity is no longer current or could not be checked. Open Nearby for fresh matches.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => Navigator.of(
                            context,
                          ).pushReplacementNamed('/nearby'),
                          child: const Text('Open Nearby'),
                        ),
                      ],
                    ),
                  ),
                );
              final forYou = List<String>.from(data!['forYou'] as List? ?? []);
              final forThem = List<String>.from(data['forThem'] as List? ?? []);
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Icon(Icons.auto_awesome, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    data['displayName'] as String? ?? 'A nearby connection',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 20),
                  if (data['modeKind'] == 'listen')
                    const Text(
                      'You are both in Listen Mode, which connects people without keyword filters.',
                    ),
                  Text(
                    'They can provide what you are searching for:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    forYou.isEmpty
                        ? 'No keyword overlap required'
                        : forYou.join(', '),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'You can provide what they are searching for:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    forThem.isEmpty
                        ? 'No keyword overlap required'
                        : forThem.join(', '),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    data['modeKind'] == 'normal'
                        ? 'When convenient, hold the Prox Circle for 3 seconds to activate Normal Active and open this connection. A meeting is not guaranteed.'
                        : 'Hold the Prox Circle for 3 seconds to open this connection. A meeting is not guaranteed.',
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: SizedBox(
                      width: 176,
                      height: 176,
                      child: ProxCircleHold(
                        enabled: !_opening,
                        onProgress: (value) {
                          if (mounted) setState(() => _progress = value);
                        },
                        onHold: _openConnection,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox.expand(
                              child: CircularProgressIndicator(
                                value: _progress,
                                strokeWidth: 6,
                              ),
                            ),
                            Text(
                              _opening ? 'Checking...' : 'Hold to connect',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacementNamed('/nearby');
                    },
                    child: const Text('Open Nearby'),
                  ),
                ],
              );
            },
          ),
  );
}
