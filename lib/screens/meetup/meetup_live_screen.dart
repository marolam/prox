import "package:prox/services/location_privacy_service.dart";
import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:geolocator/geolocator.dart";
import "package:latlong2/latlong.dart";
import "package:url_launcher/url_launcher.dart";

import "package:prox/services/meetup_service.dart";
import "package:prox/services/meetup_coordination_service.dart";
import "package:prox/widgets/color_match_button.dart";
import "package:prox/widgets/meetup_map.dart";
import "package:prox/widgets/meetup_session_bar.dart";
import "package:prox/widgets/meetup_progress_card.dart";
import "package:prox/widgets/meetup_flow_guard.dart";

class MeetupLiveScreen extends StatefulWidget {
  final String chatId;
  final String otherUid;

  const MeetupLiveScreen({
    super.key,
    required this.chatId,
    required this.otherUid,
  });

  static MeetupLiveScreen fromArgs(Object? args) {
    final m = (args is Map) ? args : <String, dynamic>{};
    return MeetupLiveScreen(
      chatId: (m["chatId"] ?? "").toString().trim(),
      otherUid: (m["otherUid"] ?? "").toString().trim(),
    );
  }

  @override
  State<MeetupLiveScreen> createState() => _MeetupLiveScreenState();
}

class _MeetupLiveScreenState extends State<MeetupLiveScreen> {
  bool _busy = false;
  bool _pushedRate = false;
  bool _ensuredRating = false;
  Timer? _locationTimer;
  bool _positionInFlight = false;
  LatLng? _myLocation;
  double? _targetLat;
  double? _targetLng;
  MeetupCoordinationInfo? _coordination;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? "";

  @override
  void initState() {
    super.initState();
    MeetupService.instance.recordSessionScreen(
      meetupId: widget.chatId,
      screen: "live",
    );
    _startLocationUpdates();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _startLocationUpdates() async {
    await _updateMyPosition();
    if (!mounted) return;
    _locationTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _updateMyPosition(),
    );
  }

  Future<void> _updateMyPosition() async {
    if (!mounted || _positionInFlight) return;
    _positionInFlight = true;
    final uid = _myUid;
    try {
      await LocationPrivacyService.instance.ensureLoaded();
      if (!mounted || !LocationPrivacyService.instance.mayReadLocation) {
        if (mounted && _myLocation != null) {
          setState(() {
            _myLocation = null;
            _coordination = null;
          });
        }
        return;
      }
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse)
        return;
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!mounted ||
          uid != _myUid ||
          !LocationPrivacyService.instance.mayReadLocation)
        return;
      final targetLat = _targetLat;
      final targetLng = _targetLng;
      setState(() {
        _myLocation = LatLng(position.latitude, position.longitude);
        _coordination = targetLat == null || targetLng == null
            ? null
            : MeetupCoordinationInfo.between(
                fromLat: position.latitude,
                fromLng: position.longitude,
                toLat: targetLat,
                toLng: targetLng,
              );
      });
    } catch (_) {
      // The meetup stays usable when a location fix is unavailable.
    } finally {
      _positionInFlight = false;
    }
  }

  void _setTarget(double lat, double lng) {
    if (_targetLat == lat && _targetLng == lng) return;
    _targetLat = lat;
    _targetLng = lng;
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateMyPosition());
  }

  Future<bool> _confirmStatus(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text("$message The other person will be notified."),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text("Not yet"),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text("Confirm"),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _runBusyAction({
    required String action,
    required Future<void> Function() task,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });
    try {
      await task();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _openMaps(double lat, double lng) async {
    final uri = Uri.parse(
      "https://www.google.com/maps/search/?api=1&query=$lat,$lng",
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _snack("Couldn't open maps.");
    }
  }

  Future<void> _onMyWay() async {
    if (!await _confirmStatus(
      "Mark yourself on the way?",
      "Only confirm when you have started traveling to the meetup.",
    ))
      return;
    await _runBusyAction(
      action: "on_my_way",
      task: () async {
        try {
          await MeetupService.instance.markOnMyWay(meetupId: widget.chatId);
          _snack("Marked as on my way.");
        } catch (_) {
          _snack("Couldn't update status.");
        }
      },
    );
  }

  Future<void> _tapToVerify() async {
    if (!await _confirmStatus(
      "Ready to verify?",
      "Confirm when you are with the other participant and ready to verify each other.",
    ))
      return;
    await _runBusyAction(
      action: "tap_verify",
      task: () async {
        try {
          final ok = await MeetupService.instance.tapToVerify(
            meetupId: widget.chatId,
          );
          _snack(
            ok
                ? "Tap-to-Verify: success"
                : "Tap-to-Verify: waiting for other tap",
          );
        } catch (_) {
          _snack("Tap-to-Verify failed.");
        }
      },
    );
  }

  Future<void> _imHerePrivacyFirst() async {
    if (!await _confirmStatus(
      "Confirm that you arrived?",
      "Only confirm when you are physically at the agreed meetup point.",
    ))
      return;
    await _runBusyAction(
      action: "im_here",
      task: () async {
        try {
          final res = await MeetupService.instance.confirmArrivalPrivacyFirst(
            meetupId: widget.chatId,
          );
          _snack(res.message);
          if (!res.isOk) {
            await _codeFallbackDialog();
          }
        } catch (_) {
          _snack("Couldn't confirm arrival.");
        }
      },
    );
  }

  Future<void> _codeFallbackDialog() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Use 4-digit code"),
          content: TextField(
            controller: c,
            maxLength: 4,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Code",
              hintText: "0000",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Confirm"),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      final res = await MeetupService.instance.confirmArrivalWithCode(
        meetupId: widget.chatId,
        code: c.text.trim(),
      );
      _snack(res.message);
    } catch (_) {
      _snack("Code confirmation failed.");
    }
  }

  void _showCodeDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Arrival code"),
        content: StreamBuilder<String>(
          stream: Stream.periodic(
            const Duration(seconds: 1),
            (_) => MeetupService.instance.arrivalCodeNow(widget.chatId),
          ),
          initialData: MeetupService.instance.arrivalCodeNow(widget.chatId),
          builder: (_, snap) => Text(
            snap.data ?? "",
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  void _ensureRatingWindowOnce() {
    if (_ensuredRating) return;
    _ensuredRating = true;
    Future<void>.microtask(() async {
      await MeetupService.instance.ensureRatingWindowOpen(widget.chatId);
    });
  }

  void _pushRateOnce() {
    if (_pushedRate) return;
    _pushedRate = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushNamed(
        "/rate",
        arguments: {"chatId": widget.chatId, "otherUid": widget.otherUid},
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _myUid;
    return MeetupFlowGuard(
      meetupId: widget.chatId,
      child: Scaffold(
        appBar: AppBar(title: const Text("Meetup: directions & arrival")),
        bottomNavigationBar: MeetupSessionBar(
          meetupId: widget.chatId,
          otherUid: widget.otherUid,
          currentScreen: "live",
          helpTitle: "Finish the meetup",
          helpMessage:
              "Travel to the agreed pin, verify together, then each person confirms arrival. Both confirmations complete the meetup and open feedback. Use Safety at any time to cancel.",
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: MeetupService.instance.watchMeetup(widget.chatId),
          builder: (context, snap) {
            if (snap.hasError)
              return const Center(
                child: Text(
                  "Couldn't load this meetup. Safety is still available above.",
                ),
              );
            if (!snap.hasData)
              return const Center(child: CircularProgressIndicator());
            final d = snap.data?.data() ?? <String, dynamic>{};
            final active = meetupIsActive(d);
            final completed = d["status"] == "completed";
            final confirmed = d["locationStatus"] == "confirmed";
            final lat = (d["lat"] as num?)?.toDouble();
            final lng = (d["lng"] as num?)?.toDouble();
            final hasPin = lat != null && lng != null;
            final arrived =
                d[myUid == d["aUid"] ? "aArrived" : "bArrived"] == true;
            final traveling =
                d[myUid == d["aUid"] ? "aOnMyWayAt" : "bOnMyWayAt"] != null;
            if (hasPin && active) _setTarget(lat, lng);
            if (!active) _locationTimer?.cancel();
            if (completed) {
              _ensureRatingWindowOnce();
              _pushRateOnce();
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                MeetupProgressCard(data: d, uid: myUid),
                if (completed)
                  FilledButton(
                    onPressed: () => Navigator.of(context).pushNamed(
                      "/rate", arguments: {"chatId": widget.chatId, "otherUid": widget.otherUid}),
                    child: const Text("Rate this meetup"),
                  ),
                if (active && (!hasPin || !confirmed)) ...[
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pushReplacementNamed(
                      "/meetup_plan",
                      arguments: {
                        "chatId": widget.chatId,
                        "otherUid": widget.otherUid,
                      },
                    ),
                    icon: const Icon(Icons.place_outlined),
                    label: const Text("Continue: review meeting point"),
                  ),
                ],
                if (active && hasPin && confirmed) ...[
                  if (!arrived) ...[
                    if (!traveling)
                      FilledButton.icon(
                        onPressed: _busy ? null : _onMyWay,
                        icon: const Icon(Icons.directions_walk),
                        label: const Text("On my way"),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _openMaps(lat, lng),
                      icon: const Icon(Icons.directions),
                      label: const Text("Open directions to the agreed pin"),
                    ),
                    const SizedBox(height: 12),
                    _infoCard(
                      context,
                      title: "Together at the meeting point?",
                      lines: const [
                        "Both people tap Verify together while standing together, then each taps Confirm my arrival.",
                        "If verification or location does not work, show your arrival code and use Enter arrival code. Codes change every 30 seconds.",
                        "Arrival completes the meetup only after both people confirm. A code is a fallback, not proof of someone's identity.",
                      ],
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _tapToVerify,
                      icon: const Icon(Icons.touch_app),
                      label: const Text("Verify together"),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _showCodeDialog,
                          icon: const Icon(Icons.password),
                          label: const Text("Show arrival code"),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _codeFallbackDialog,
                          icon: const Icon(Icons.dialpad),
                          label: const Text("Enter arrival code"),
                        ),
                      ],
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _imHerePrivacyFirst,
                      icon: const Icon(Icons.flag_circle),
                      label: Text(_busy ? "Saving..." : "Confirm my arrival"),
                    ),
                    Center(
                      child: ColorMatchButton(
                        meetupId: widget.chatId,
                        onStarted: () {},
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    "Your agreed meeting point - locked after confirmation",
                  ),
                  SizedBox(
                    height: 260,
                    child: MeetupMap(
                      center: LatLng(lat, lng),
                      myLocation: _myLocation,
                    ),
                  ),
                  if (_coordination != null)
                    Text(
                      "${_coordination!.distanceLabel} straight-line distance - about ${_coordination!.roughWalkingMinutes} min walking. This estimate does not account for roads or entrances.",
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _infoCard(
    BuildContext context, {
    required String title,
    required List<String> lines,
    Widget? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: DefaultTextStyle(
              style:
                  Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        l,
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.80),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}
