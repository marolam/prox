import "package:prox/services/location_privacy_service.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:geolocator/geolocator.dart";
import "package:latlong2/latlong.dart";

import "package:prox/services/meetup_service.dart";
import "package:prox/widgets/meetup_session_bar.dart";
import "package:prox/widgets/meetup_map.dart";
import "package:prox/widgets/meetup_progress_card.dart";
import "package:prox/widgets/meetup_flow_guard.dart";

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
  LatLng? _dragPreview;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? "";

  @override
  void initState() {
    super.initState();
    MeetupService.instance.recordSessionScreen(
      meetupId: widget.chatId,
      screen: "planner",
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _pinFailureMessage(Object error) {
    if (error is FirebaseException) {
      if (error.code == "permission-denied") {
        return "Pin update was denied. Reopen this meetup and try again.";
      }
      if (error.code == "unavailable") {
        return "Pin update needs a network connection. Try again.";
      }
    }
    if (error is ArgumentError) {
      return "This meetup is missing valid participant or location details.";
    }
    if (error is StateError) {
      return "Sign in again, then reopen this meetup.";
    }
    return "Couldn't update meetup pin. Please try again.";
  }

  Future<Position?> _bestEffortPosition() async {
    await LocationPrivacyService.instance.ensureLoaded();
    if (!LocationPrivacyService.instance.mayReadLocation) return null;
    final uid = _myUid;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      final granted =
          perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
      if (!granted) return null;

      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return uid == _myUid && LocationPrivacyService.instance.mayReadLocation
          ? position
          : null;
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
        _snack(
          "Enable location in Prox Settings and your device settings to use your position.",
        );
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
    } catch (error) {
      _snack(_pinFailureMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveMapPin(LatLng point) async {
    final myUid = _myUid;
    if (myUid.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _dragPreview = point;
    });
    try {
      await MeetupService.instance.ensureMeetup(
        chatId: widget.chatId,
        aUid: myUid,
        bUid: widget.otherUid,
        lat: point.latitude,
        lng: point.longitude,
      );
      _snack("Meetup pin shared.");
    } catch (error) {
      _snack(_pinFailureMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _dragPreview = null;
        });
      }
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: "Latitude"),
              ),
              TextField(
                controller: lngC,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: "Longitude"),
              ),
              const SizedBox(height: 8),
              const Text(
                "Tip: use Google Maps to copy coordinates, paste here.",
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Save"),
            ),
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
    } catch (error) {
      _snack(_pinFailureMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmLocation() async {
    final myUid = _myUid;
    if (myUid.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm this meetup location?"),
        content: const Text(
          "You are agreeing to meet at the displayed pin. The other person will be notified.",
        ),
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
    );
    if (confirmed != true || !mounted) return;
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
              Text(
                "Meetup planning help",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 10),
              Text(" Planner sets the pin (Use my location / Move pin)."),
              Text(" The other person confirms the pin to avoid surprises."),
              Text(" After confirmation, open Live Meetup to share progress."),
              SizedBox(height: 10),
              Text(
                "Tip: Pick an obvious spot: entrance, landmark, or a specific store front.",
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _myUid;

    return MeetupFlowGuard(
      meetupId: widget.chatId,
      child: Scaffold(
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
        bottomNavigationBar: MeetupSessionBar(
          meetupId: widget.chatId,
          otherUid: widget.otherUid,
          currentScreen: "planner",
          helpTitle: "Plan the meetup",
          helpMessage:
              "Set one clear public meeting point. The other person confirms it, then both of you open Live and update each step as it happens.",
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: MeetupService.instance.watchMeetup(widget.chatId),
          builder: (context, snap) {
            if (snap.hasError)
              return const Center(
                child: Text(
                  "Could not load the meeting point. Check your connection. Safety is available above.",
                ),
              );
            if (!snap.hasData)
              return const Center(child: CircularProgressIndicator());
            final bool exists = snap.data?.exists == true;
            final d = snap.data?.data() ?? <String, dynamic>{};

            final String plannerUid = (d["plannerUid"] ?? "").toString().trim();
            final bool iAmPlanner = plannerUid.isEmpty
                ? true
                : plannerUid == myUid;

            final String locStatus = (d["locationStatus"] ?? "")
                .toString()
                .trim();
            final double? lat = (d["lat"] is num)
                ? (d["lat"] as num).toDouble()
                : double.tryParse((d["lat"] ?? "").toString());
            final double? lng = (d["lng"] is num)
                ? (d["lng"] as num).toDouble()
                : double.tryParse((d["lng"] ?? "").toString());
            final bool hasPin = lat != null && lng != null;
            final LatLng? displayedPin =
                _dragPreview ?? (hasPin ? LatLng(lat, lng) : null);

            if (!exists) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                children: [
                  _infoCard(
                    context,
                    title: "Meetup not created yet",
                    lines: const [
                      "Agree to a meetup in chat before choosing a meeting point.",
                      "Return to chat to send or accept the request.",
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text("Back to chat"),
                    ),
                  ),
                ],
              );
            }

            if (!meetupIsActive(d)) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [MeetupProgressCard(data: d, uid: myUid)],
              );
            }
            if (d["status"] == "requested") {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  MeetupProgressCard(data: d, uid: myUid),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacementNamed(
                      "/chat",
                      arguments: {
                        "chatId": widget.chatId,
                        "otherUid": widget.otherUid,
                      },
                    ),
                    child: const Text("Respond in chat"),
                  ),
                ],
              );
            }
            final canMovePin = iAmPlanner && locStatus != "confirmed";
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              children: [
                MeetupProgressCard(data: d, uid: myUid),
                const SizedBox(height: 12),
                if (displayedPin != null) ...[
                  SizedBox(
                    height: 330,
                    child: MeetupMap(
                      key: ValueKey<String>("meetup-map-${widget.chatId}"),
                      center: displayedPin,
                      onPinDrag: canMovePin
                          ? (point) => setState(() => _dragPreview = point)
                          : null,
                      onPinDragEnd: canMovePin ? _saveMapPin : null,
                      onLongPress: canMovePin ? _saveMapPin : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    canMovePin
                        ? "Drag the orange pin or press and hold the map to move it. Release to share the new location."
                        : "The meetup pin updates here when the planner moves it.",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (canMovePin) ...[
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
                      child: Text(
                        "Enter coordinates instead",
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ] else if (!iAmPlanner && locStatus != "confirmed") ...[
                  _infoCard(
                    context,
                    title: "Review their meeting point",
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
                        arguments: {
                          "chatId": widget.chatId,
                          "otherUid": widget.otherUid,
                        },
                      );
                    },
                    icon: const Icon(Icons.directions_walk),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        "Continue to directions & arrival",
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ] else if (!hasPin) ...[
                  _infoCard(
                    context,
                    title: "Next step",
                    lines: const ["Set a pin to start the live meetup flow."],
                  ),
                ] else if (!iAmPlanner && locStatus != "confirmed") ...[
                  _infoCard(
                    context,
                    title: "Next step",
                    lines: const ["Confirm the pin to unlock Live Meetup."],
                  ),
                ] else if (iAmPlanner && locStatus != "confirmed") ...[
                  _infoCard(
                    context,
                    title: "Next step",
                    lines: const [
                      "Wait for the other person to confirm the pin.",
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
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
