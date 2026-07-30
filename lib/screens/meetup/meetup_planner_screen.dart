import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:geolocator/geolocator.dart";
import "package:url_launcher/url_launcher.dart";

import "package:prox/services/meetup_service.dart";

class MeetupPlannerScreen extends StatefulWidget {
  final String chatId;
  final String otherUid;

  const MeetupPlannerScreen({
    super.key,
    required this.chatId,
    required this.otherUid,
  });

  static MeetupPlannerScreen fromArgs(Object? args) {
    final m = (args is Map) ? args : <String, dynamic>{};
    return MeetupPlannerScreen(
      chatId: (m["chatId"] ?? "").toString().trim(),
      otherUid: (m["otherUid"] ?? "").toString().trim(),
    );
  }

  @override
  State<MeetupPlannerScreen> createState() => _MeetupPlannerScreenState();
}

class _MeetupPlannerScreenState extends State<MeetupPlannerScreen> {
  bool _busy = false;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? "";

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<Position?> _bestEffortPosition() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      final granted =
          perm == LocationPermission.always || perm == LocationPermission.whileInUse;
      if (!granted) return null;

      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _setPinToMyLocation() async {
    final myUid = _myUid;
    if (myUid.isEmpty) {
      _snack("Sign in to plan a meetup.");
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final pos = await _bestEffortPosition();
      if (pos == null) {
        _snack("Location permission/services needed.");
        return;
      }

      await MeetupService.instance.ensureMeetup(
        chatId: widget.chatId,
        aUid: myUid,
        bUid: widget.otherUid,
        lat: pos.latitude,
        lng: pos.longitude,
      );
      _snack("Meetup pin updated.");
    } catch (_) {
      _snack("Couldn't update meetup pin.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _promptMovePin() async {
    final myUid = _myUid;
    if (myUid.isEmpty) {
      _snack("Sign in to plan a meetup.");
      return;
    }

    final latC = TextEditingController();
    final lngC = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Move pin"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: latC,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: "Latitude"),
              ),
              TextField(
                controller: lngC,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: "Longitude"),
              ),
              const SizedBox(height: 8),
              const Text("Tip: use Google Maps to copy coordinates, paste here."),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Save")),
          ],
        );
      },
    );

    if (ok != true) return;

    final lat = double.tryParse(latC.text.trim());
    final lng = double.tryParse(lngC.text.trim());
    if (lat == null || lng == null) {
      _snack("Invalid coordinates.");
      return;
    }

    if (_busy) return;
    setState(() => _busy = true);
    try {
      await MeetupService.instance.ensureMeetup(
        chatId: widget.chatId,
        aUid: myUid,
        bUid: widget.otherUid,
        lat: lat,
        lng: lng,
      );
      _snack("Meetup pin updated.");
    } catch (_) {
      _snack("Couldn't update meetup pin.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMaps(double lat, double lng) async {
    final uri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng");
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _snack("Couldn't open maps.");
    }
  }

  Future<void> _confirmLocation() async {
    final myUid = _myUid;
    if (myUid.isEmpty) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await MeetupService.instance.confirmLocation(meetupId: widget.chatId);
      _snack("Location confirmed.");
    } catch (_) {
      _snack("Couldn't confirm location.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showHelp() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text("Meetup planning help", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              SizedBox(height: 10),
              Text(" Planner sets the pin (Use my location / Move pin)."),
              Text(" The other person confirms the pin to avoid surprises."),
              Text(" After confirmation, open Live Meetup to share progress."),
              SizedBox(height: 10),
              Text("Tip: Pick an obvious spot: entrance, landmark, or a specific store front."),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _myUid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Plan meetup"),
        actions: [
          IconButton(
            tooltip: "Help",
            onPressed: _showHelp,
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: MeetupService.instance.watchMeetup(widget.chatId),
        builder: (context, snap) {
          final bool exists = snap.data?.exists == true;
          final d = snap.data?.data() ?? <String, dynamic>{};

          final String plannerUid = (d["plannerUid"] ?? "").toString().trim();
          final bool iAmPlanner = plannerUid.isEmpty ? true : plannerUid == myUid;

          final String locStatus = (d["locationStatus"] ?? "").toString().trim();
          final double? lat =
              (d["lat"] is num) ? (d["lat"] as num).toDouble() : double.tryParse((d["lat"] ?? "").toString());
          final double? lng =
              (d["lng"] is num) ? (d["lng"] as num).toDouble() : double.tryParse((d["lng"] ?? "").toString());
          final bool hasPin = lat != null && lng != null;

          if (!exists) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              children: [
                _infoCard(
                  context,
                  title: "Meetup not created yet",
                  lines: const [
                    "This chat may not have an active meetup doc yet.",
                    "If the meetup request was accepted, the planner can create it by setting a pin.",
                  ],
                ),
                const SizedBox(height: 12),
                if (iAmPlanner)
                  FilledButton.icon(
                    onPressed: _busy ? null : _setPinToMyLocation,
                    icon: const Icon(Icons.my_location),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_busy ? "Working..." : "Create meetup (use my location)"),
                    ),
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text("Back to chat"),
                  ),
                ),
              ],
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            children: [
              _infoCard(
                context,
                title: "Status",
                lines: [
                  "Pick a pin, then confirm together before heading out.",
                  "Planner: ${plannerUid.isEmpty ? "(unset)" : plannerUid}",
                  "Location: ${locStatus.isEmpty ? "none" : locStatus}",
                  if (hasPin) "Pin: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}" else "Pin: (not set)",
                ],
                trailing: hasPin
                    ? IconButton(
                        tooltip: "Open in Maps",
                        onPressed: () => _openMaps(lat, lng),
                        icon: const Icon(Icons.map_outlined),
                      )
                    : null,
              ),
              const SizedBox(height: 12),

              if (iAmPlanner) ...[
                FilledButton.icon(
                  onPressed: _busy ? null : _setPinToMyLocation,
                  icon: const Icon(Icons.my_location),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _busy ? "Working..." : "Set pin to my location",
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _promptMovePin,
                  icon: const Icon(Icons.edit_location_alt),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text("Move pin manually (coords)", style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ] else ...[
                _infoCard(
                  context,
                  title: "You are not the planner",
                  lines: const [
                    "Wait for the planner to set the pin, then confirm it to unlock Live Meetup.",
                  ],
                ),
              ],

              const SizedBox(height: 14),

              if (!iAmPlanner && hasPin && locStatus != "confirmed") ...[
                FilledButton.icon(
                  onPressed: _busy ? null : _confirmLocation,
                  icon: const Icon(Icons.verified),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_busy ? "Working..." : "Confirm location"),
                  ),
                ),
              ],

              if (hasPin && locStatus == "confirmed") ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      "/meetup_live",
                      arguments: {"chatId": widget.chatId, "otherUid": widget.otherUid},
                    );
                  },
                  icon: const Icon(Icons.directions_walk),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text("Open live meetup", style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ] else if (!hasPin) ...[
                _infoCard(context, title: "Next step", lines: const ["Set a pin to start the live meetup flow."]),
              ] else if (!iAmPlanner && locStatus != "confirmed") ...[
                _infoCard(context, title: "Next step", lines: const ["Confirm the pin to unlock Live Meetup."]),
              ] else if (iAmPlanner && locStatus != "confirmed") ...[
                _infoCard(context, title: "Next step", lines: const ["Wait for the other person to confirm the pin."]),
              ],

              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text("Back to chat"),
                ),
              ),
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
              style: Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(l, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.80))),
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
