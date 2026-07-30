import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:url_launcher/url_launcher.dart";

import "package:prox/services/meetup_service.dart";
import "package:prox/widgets/color_match_button.dart";

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
  String _busyAction = "";
  bool _pushedRate = false;
  bool _ensuredRating = false;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? "";

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool _isBusy(String action) => _busy && _busyAction == action;

  Future<void> _runBusyAction({
    required String action,
    required Future<void> Function() task,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyAction = action;
    });
    try {
      await task();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyAction = "";
        });
      }
    }
  }

  Future<void> _openMaps(double lat, double lng) async {
    final uri =
        Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng");
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _snack("Couldn't open maps.");
    }
  }

  Future<void> _confirmLocation() async {
    await _runBusyAction(
      action: "confirm_location",
      task: () async {
        try {
          await MeetupService.instance.confirmLocation(meetupId: widget.chatId);
          _snack("Location confirmed.");
        } catch (_) {
          _snack("Couldn't confirm location.");
        }
      },
    );
  }

  Future<void> _onMyWay() async {
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
    await _runBusyAction(
      action: "tap_verify",
      task: () async {
        try {
          final ok =
              await MeetupService.instance.tapToVerify(meetupId: widget.chatId);
          _snack(ok
              ? "Tap-to-Verify: success"
              : "Tap-to-Verify: waiting for other tap");
        } catch (_) {
          _snack("Tap-to-Verify failed.");
        }
      },
    );
  }

  Future<void> _imHerePrivacyFirst() async {
    await _runBusyAction(
      action: "im_here",
      task: () async {
        try {
          final res = await MeetupService.instance
              .confirmArrivalPrivacyFirst(meetupId: widget.chatId);
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
                child: const Text("Cancel")),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text("Confirm")),
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
    final code = MeetupService.instance.arrivalCodeNow(widget.chatId);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Arrival code"),
        content: Text(
          code,
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Close")),
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

  String _fmtTs(dynamic v) {
    if (v is Timestamp) {
      final dt = v.toDate();
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, "0");
      final ap = dt.hour >= 12 ? "PM" : "AM";
      return "${dt.month}/${dt.day} $h:$m $ap";
    }
    return "";
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _myUid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Live meetup"),
        actions: [
          IconButton(
            tooltip: "Show code",
            onPressed: _showCodeDialog,
            icon: const Icon(Icons.password),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: MeetupService.instance.watchMeetup(widget.chatId),
        builder: (context, snap) {
          final bool exists = snap.data?.exists == true;
          final d = snap.data?.data() ?? <String, dynamic>{};

          if (!exists) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              children: [
                _infoCard(
                  context,
                  title: "Meetup not ready",
                  lines: const [
                    "The planner hasn't created the meetup yet (no pin).",
                    "Go back to the planner and set a pin.",
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text("Back"),
                  ),
                ),
              ],
            );
          }

          final String status = (d["status"] ?? "").toString().trim();
          final bool completed = status == "completed";

          final String plannerUid = (d["plannerUid"] ?? "").toString().trim();
          final bool iAmPlanner =
              plannerUid.isEmpty ? true : plannerUid == myUid;

          final String locStatus =
              (d["locationStatus"] ?? "").toString().trim();
          final double? lat = (d["lat"] is num)
              ? (d["lat"] as num).toDouble()
              : double.tryParse((d["lat"] ?? "").toString());
          final double? lng = (d["lng"] is num)
              ? (d["lng"] as num).toDouble()
              : double.tryParse((d["lng"] ?? "").toString());
          final bool hasPin = lat != null && lng != null;

          final bool aArrived = (d["aArrived"] as bool?) ?? false;
          final bool bArrived = (d["bArrived"] as bool?) ?? false;

          final String aUid = (d["aUid"] ?? "").toString().trim();
          final String bUid = (d["bUid"] ?? "").toString().trim();
          final bool isA = myUid.isNotEmpty && myUid == aUid;
          final bool isB = myUid.isNotEmpty && myUid == bUid;

          final String onMyWayField =
              isA ? "aOnMyWayAt" : (isB ? "bOnMyWayAt" : "");
          final String otherOnMyWayField =
              isA ? "bOnMyWayAt" : (isB ? "aOnMyWayAt" : "");
          final String onMyWayAt =
              (onMyWayField.isEmpty) ? "" : _fmtTs(d[onMyWayField]);
          final String otherOnMyWayAt =
              (otherOnMyWayField.isEmpty) ? "" : _fmtTs(d[otherOnMyWayField]);

          final bool needConfirm =
              (!iAmPlanner && locStatus != "confirmed" && hasPin);
          final bool confirmed = locStatus == "confirmed";
          final bool canRunLiveActions = hasPin && confirmed;

          if (completed) {
            _ensureRatingWindowOnce();
            _pushRateOnce();
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            children: [
              _infoCard(
                context,
                title: completed ? "Meetup completed" : "Meetup",
                lines: [
                  "Status: ${status.isEmpty ? "(unknown)" : status}",
                  "Location: ${locStatus.isEmpty ? "none" : locStatus}",
                  if (hasPin)
                    "Pin: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}",
                  if (onMyWayAt.isNotEmpty) "You: on my way at $onMyWayAt",
                  if (otherOnMyWayAt.isNotEmpty)
                    "Them: on my way at $otherOnMyWayAt",
                  "Arrived: you=${(isA ? aArrived : (isB ? bArrived : false))}  them=${(isA ? bArrived : (isB ? aArrived : false))}",
                ],
                trailing: hasPin
                    ? IconButton(
                        tooltip: "Open Maps",
                        onPressed: () => _openMaps(lat, lng),
                        icon: const Icon(Icons.map_outlined),
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              if (completed) ...[
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      "/rate",
                      arguments: {
                        "chatId": widget.chatId,
                        "otherUid": widget.otherUid
                      },
                    );
                  },
                  icon: const Icon(Icons.star_rate),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text("Rate now"),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text("Back"),
                  ),
                ),
              ] else ...[
                if (needConfirm)
                  FilledButton.icon(
                    onPressed: _busy ? null : _confirmLocation,
                    icon: const Icon(Icons.verified),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_busy ? "Working..." : "Confirm location"),
                    ),
                  ),
                if (!confirmed)
                  _infoCard(
                    context,
                    title: "Heads up",
                    lines: const [
                      "Confirming the pin prevents surprises. Once confirmed, proceed with On my way / Tap-to-Verify / I'm here."
                    ],
                  ),
                if (canRunLiveActions) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : _onMyWay,
                    icon: const Icon(Icons.directions_walk),
                    label: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                          _isBusy("on_my_way") ? "Updating..." : "On my way"),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _tapToVerify,
                    icon: const Icon(Icons.touch_app),
                    label: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(_isBusy("tap_verify")
                          ? "Verifying..."
                          : "Tap-to-Verify"),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: ColorMatchButton(
                      meetupId: widget.chatId,
                      onStarted: () {},
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : _imHerePrivacyFirst,
                    icon: const Icon(Icons.flag_circle),
                    label: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                          _isBusy("im_here") ? "Confirming..." : "I'm here"),
                    ),
                  ),
                ] else if (hasPin && !confirmed) ...[
                  const SizedBox(height: 10),
                  _infoCard(
                    context,
                    title: "Confirm location first",
                    lines: const [
                      "Live actions unlock right after both sides confirm the meetup pin.",
                    ],
                  ),
                ] else ...[
                  _infoCard(
                    context,
                    title: "No pin yet",
                    lines: const ["Go back and set a pin in the planner."],
                  ),
                ],
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text("Back"),
                  ),
                ),
              ],
            ],
          );
        },
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
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(l,
                          style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.80))),
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
