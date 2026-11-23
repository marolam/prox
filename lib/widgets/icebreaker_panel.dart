import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:prox/services/icebreaker_service.dart';
import 'package:prox/services/location_privacy_service.dart';

const _signalColors = <Color>[
  Color(0xFFFFB74D),
  Color(0xFF64B5F6),
  Color(0xFFCE93D8),
  Color(0xFF4DD0E1),
  Color(0xFFFF8A80),
  Color(0xFFAED581),
  Color(0xFFF48FB1),
  Color(0xFFFFF176),
];
const _signalSymbols = <IconData>[
  Icons.star_outline,
  Icons.favorite_border,
  Icons.bolt,
  Icons.diamond_outlined,
  Icons.spa_outlined,
  Icons.waves,
  Icons.wb_sunny_outlined,
  Icons.nights_stay_outlined,
];
const _symbolNames = <String>[
  'star',
  'heart',
  'bolt',
  'diamond',
  'leaf',
  'waves',
  'sun',
  'moon',
];
const _colorNames = <String>[
  'amber',
  'blue',
  'purple',
  'cyan',
  'coral',
  'green',
  'pink',
  'yellow',
];

String? icebreakerCodeFromQr(String value) {
  final match = RegExp(r'^prox-icebreaker:([A-F0-9]{10})$').firstMatch(value);
  return match?.group(1);
}

class IcebreakerPanel extends StatefulWidget {
  const IcebreakerPanel({
    super.key,
    required this.uid,
    required this.onMode,
    required this.circleKey,
  });
  final String uid;
  final Future<void> Function() onMode;
  final Key circleKey;

  @override
  State<IcebreakerPanel> createState() => _IcebreakerPanelState();
}

class _IcebreakerPanelState extends State<IcebreakerPanel>
    with WidgetsBindingObserver {
  final _service = IcebreakerService();
  Timer? _timer;
  StreamSubscription<User?>? _auth;
  bool _choosingMode = false;
  bool _foreground = true;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    LocationPrivacyService.instance.addListener(_updateAvailability);
    _auth = FirebaseAuth.instance.authStateChanges().listen((user) {
      _updateAvailability();
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    await LocationPrivacyService.instance.ensureLoaded();
    if (mounted) _updateAvailability();
  }

  void _updateAvailability() {
    final allowed =
        mounted &&
        _foreground &&
        !_choosingMode &&
        LocationPrivacyService.instance.locationEnabled &&
        FirebaseAuth.instance.currentUser?.uid == widget.uid;
    if (!allowed) {
      _timer?.cancel();
      _timer = null;
      unawaited(_service.stop());
      return;
    }
    if (_timer != null) return;
    unawaited(_service.start(widget.uid));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _service.expire();
      if (++_ticks % 5 == 0) unawaited(_service.refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updateAvailability();
  }

  Future<void> _chooseMode() async {
    _choosingMode = true;
    _updateAvailability();
    await widget.onMode();
    if (!mounted) return;
    _choosingMode = false;
    _updateAvailability();
  }

  Future<void> _confirmEncounter() async {
    if (!_service.live || _service.code == null) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => _EncounterCodeDialog(service: _service),
    );
    if (!mounted || selected == null) return;
    final code = selected == '__scan__'
        ? await Navigator.of(context).push<String>(
            MaterialPageRoute(builder: (_) => const _IcebreakerScanner()),
          )
        : selected;
    if (mounted && code != null) await _service.join(code);
  }

  Future<void> _openParty() async {
    _choosingMode = true;
    _updateAvailability();
    await Navigator.of(context).pushNamed('/party');
    if (!mounted) return;
    _choosingMode = false;
    _updateAvailability();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LocationPrivacyService.instance.removeListener(_updateAvailability);
    _auth?.cancel();
    _timer?.cancel();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) => IcebreakerView(
        service: _service,
        circleKey: widget.circleKey,
        locationEnabled: LocationPrivacyService.instance.locationEnabled,
        onMode: _chooseMode,
        onConfirm: _confirmEncounter,
        onParty: _openParty,
      ),
    );
  }
}

class IcebreakerView extends StatelessWidget {
  const IcebreakerView({
    super.key,
    required this.service,
    required this.circleKey,
    required this.locationEnabled,
    required this.onMode,
    required this.onConfirm,
    required this.onParty,
  });
  final IcebreakerService service;
  final Key circleKey;
  final bool locationEnabled;
  final VoidCallback onMode;
  final VoidCallback onConfirm;
  final VoidCallback onParty;

  void _showSignal(BuildContext context, IcebreakerSignal signal) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ListenableBuilder(
          listenable: service,
          builder: (context, _) {
            final current =
                service.live &&
                service.signals.any((item) => item.key == signal.key);
            return Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (current) ...[
                    Icon(
                      _signalSymbols[signal.symbolIndex],
                      size: 100,
                      color: _signalColors[signal.colorIndex],
                    ),
                    Text(
                      signal.mark,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const Text(
                      'Compare color, symbol, and mark. Confirm with a code before sharing keywords.',
                    ),
                  ] else
                    const Text(
                      'This signal faded. Return to Nearby to refresh.',
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back to Nearby'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final live = service.live;
    final signals = live ? service.signals : const <IcebreakerSignal>[];
    final primary = signals.isEmpty ? null : signals.first;
    final nearby = live && service.nearby;
    final glow = primary != null
        ? _signalColors[primary.colorIndex]
        : service.band == 'close'
        ? const Color(0xFFFFB74D)
        : service.band == 'near'
        ? const Color(0xFFFFE082)
        : const Color(0xFF90CAF9);
    final strength = !nearby
        ? 0.0
        : service.band == 'close'
        ? 0.45
        : service.band == 'near'
        ? 0.3
        : 0.18;
    final encounter = live ? service.encounter : null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            glow.withValues(alpha: strength),
            Colors.transparent,
          ],
          radius: 1.1,
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Nearby / Icebreaker',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(onPressed: onMode, child: const Text('Mode')),
            ],
          ),
          const Text(
            'Open to a spontaneous hello. No match cards, chat requests, or obligation to respond.',
          ),
          const SizedBox(height: 24),
          Center(
            child: Semantics(
              label: !nearby
                  ? 'Icebreaker circle, no current nearby signal'
                  : primary == null
                  ? 'Icebreaker circle, approximate proximity'
                  : 'Icebreaker circle, compatible keywords nearby',
              child: AnimatedContainer(
                key: circleKey,
                duration: const Duration(milliseconds: 700),
                width: 196,
                height: 196,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: nearby ? glow : Colors.grey,
                    width: 3,
                  ),
                  color: glow.withValues(alpha: strength / 2),
                  boxShadow: nearby
                      ? [
                          BoxShadow(
                            color: glow.withValues(alpha: strength),
                            blurRadius: 45,
                            spreadRadius: 8,
                          ),
                        ]
                      : [],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      primary == null
                          ? Icons.waving_hand_outlined
                          : _signalSymbols[primary.symbolIndex],
                      size: 56,
                      color: nearby ? glow : Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'ICEBREAKER',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (primary != null) Text(primary.mark),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (!locationEnabled)
            const Text(
              'Location is off. Enable location in Settings to participate.',
            )
          else if (service.error != null)
            Text(service.error!)
          else if (!live)
            const Text(
              'Refreshing proximity. Signals stay dark until a fresh observation arrives.',
            )
          else if (!nearby) ...[
            const Text(
              'No Icebreakers nearby right now. You can still explore connections within your party.',
            ),
            TextButton(onPressed: onParty, child: const Text('Explore Party')),
          ] else
            Text(
              primary == null
                  ? 'A participant appears nearby. A soft glow indicates proximity, not keyword compatibility.'
                  : 'Compatible keywords nearby. Compare a shared color, symbol, and mark with someone who chooses to show their screen.',
            ),
          if (signals.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Show my signal'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: signals
                  .map(
                    (signal) => OutlinedButton.icon(
                      onPressed: () => _showSignal(context, signal),
                      icon: Icon(
                        _signalSymbols[signal.symbolIndex],
                        color: _signalColors[signal.colorIndex],
                      ),
                      label: Text(
                        '${_colorNames[signal.colorIndex]} ${_symbolNames[signal.symbolIndex]} ${signal.mark}',
                      ),
                    ),
                  )
                  .toList(),
            ),
            if (signals.length > 1)
              const Text(
                'Several shared signals are possible. Choose the one you both see.',
              ),
          ],
          const SizedBox(height: 16),
          if (!service.hasEncounter)
            FilledButton.icon(
              onPressed: live && !service.busy ? onConfirm : null,
              icon: const Icon(Icons.qr_code_2),
              label: const Text('We found each other'),
            ),
          if (encounter != null) ...[
            const Text(
              'Encounter confirmed. Keyword sharing and Party are separate choices.',
            ),
            if (!encounter.revealed) ...[
              FilledButton(
                onPressed: service.busy || encounter.myReveal
                    ? null
                    : service.reveal,
                child: Text(
                  encounter.myReveal
                      ? 'Waiting for their keyword consent'
                      : 'Agree to reveal our connecting keywords',
                ),
              ),
              const Text(
                'Only the keywords connecting you and your display names are revealed, after both agree.',
              ),
            ] else ...[
              Text(
                'Your connection with ${encounter.peerName}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (encounter.keywords.isEmpty)
                const Text(
                  'No connecting keywords right now. You can still choose to stay connected.',
                )
              else
                Wrap(
                  spacing: 6,
                  children: encounter.keywords
                      .map((keyword) => Chip(label: Text(keyword)))
                      .toList(),
                ),
              if (encounter.connected)
                const Text(
                  'You both agreed. You are now in each other\'s party.',
                )
              else
                FilledButton(
                  onPressed: service.busy || encounter.myAdd
                      ? null
                      : service.addToParty,
                  child: Text(
                    encounter.myAdd
                        ? 'Waiting for their Party choice'
                        : 'Agree to add each other to Party',
                  ),
                ),
            ],
          ],
          if (service.hasEncounter || service.error != null)
            TextButton(
              onPressed: service.busy ? null : service.cancelEncounter,
              child: const Text(
                'End encounter (keeps any agreed Party connection)',
              ),
            ),
          TextButton(
            onPressed: service.busy ? null : service.refresh,
            child: const Text('Refresh'),
          ),
          if (service.busy) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          const Text(
            'Approximate GPS pilot: both people must opt in and keep Nearby open. Brighter / warmer ambient glow suggests closer proximity. Shared signals are not proof of identity or the same room. No exact location, direction, or background alerts. Leaving Nearby or turning location off ends participation.',
          ),
        ],
      ),
    );
  }
}

class _EncounterCodeDialog extends StatefulWidget {
  const _EncounterCodeDialog({required this.service});
  final IcebreakerService service;
  @override
  State<_EncounterCodeDialog> createState() => _EncounterCodeDialogState();
}

class _EncounterCodeDialogState extends State<_EncounterCodeDialog> {
  final _input = TextEditingController();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.service,
      builder: (context, _) {
        final code = widget.service.live ? widget.service.code : null;
        final paired = widget.service.hasEncounter;
        return AlertDialog(
          title: const Text('We found each other'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Stand together. One person scans or enters the other person\'s code. This does not reveal keywords or add anyone to Party. Both choose separately afterward.',
                ),
                const SizedBox(height: 12),
                if (paired)
                  const Text(
                    'Encounter confirmed. Close this window to choose whether to reveal keywords.',
                  )
                else if (code != null) ...[
                  QrImageView(
                    data: 'prox-icebreaker:$code',
                    size: 170,
                    backgroundColor: Colors.white,
                  ),
                  SelectableText(code),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _input,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 10,
                    decoration: const InputDecoration(
                      labelText: 'Their Icebreaker code',
                    ),
                  ),
                ] else
                  const Text(
                    'Your code expired or proximity is unavailable. Return to Nearby to refresh.',
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to Nearby'),
            ),
            if (!paired &&
                (kIsWeb ||
                    defaultTargetPlatform == TargetPlatform.android ||
                    defaultTargetPlatform == TargetPlatform.iOS ||
                    defaultTargetPlatform == TargetPlatform.macOS))
              TextButton(
                onPressed: code == null
                    ? null
                    : () => Navigator.pop(context, '__scan__'),
                child: const Text('Scan their QR'),
              ),
            if (!paired)
              FilledButton(
                onPressed: code == null
                    ? null
                    : () => Navigator.pop(context, _input.text),
                child: const Text('Confirm code'),
              ),
          ],
        );
      },
    );
  }
}

class _IcebreakerScanner extends StatefulWidget {
  const _IcebreakerScanner();
  @override
  State<_IcebreakerScanner> createState() => _IcebreakerScannerState();
}

class _IcebreakerScannerState extends State<_IcebreakerScanner> {
  bool _found = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan their Icebreaker QR')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Scan the code shown in their Nearby / Icebreaker screen. No keywords are revealed by scanning.',
            ),
          ),
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                if (_found) return;
                for (final barcode in capture.barcodes) {
                  final code = icebreakerCodeFromQr(barcode.rawValue ?? '');
                  if (code != null) {
                    _found = true;
                    Navigator.pop(context, code);
                    return;
                  }
                }
                if (_error == null)
                  setState(
                    () => _error = 'That is not an Icebreaker code. Scan their current Nearby code.',
                  );
              },
              errorBuilder: (context, error) => Center(
                child: Text(
                  'Camera unavailable: ${error.errorCode.name}. Go back and enter their code instead.',
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back / enter code instead'),
          ),
        ],
      ),
    );
  }
}
