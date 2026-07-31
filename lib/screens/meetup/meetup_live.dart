import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:geolocator/geolocator.dart";
import "package:image_picker/image_picker.dart";
import "package:url_launcher/url_launcher.dart";

import "package:prox/services/chat_media_service.dart";
import "package:prox/services/chat_service.dart";
import "package:prox/services/meetup_service.dart";
import "package:prox/widgets/rating_sheet.dart";

class MeetupLiveScreen extends StatefulWidget {
  final String meetupId;
  final String chatId;
  final String aUid;
  final String bUid;

  const MeetupLiveScreen({
    super.key,
    required this.meetupId,
    required this.chatId,
    required this.aUid,
    required this.bUid,
  });

  @override
  State<MeetupLiveScreen> createState() => _MeetupLiveScreenState();
}

class _MeetupLiveScreenState extends State<MeetupLiveScreen> {
  Timer? _pollTimer;
  bool _locationReady = false;
  bool _autoConfirmSent = false;

  double? _targetLat;
  double? _targetLng;
  String _targetStatus = "";
  bool _meArrived = false;

  double? _currentDistanceMeters;
  DateTime? _closeEnoughSince;
  String? _autoConfirmNote;

  bool _ratingOpened = false;

  @override
  void initState() {
    super.initState();
    _initLocationPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    super.dispose();
  }

  Future<void> _initLocationPolling() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }

      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;

      if (!mounted) return;
      setState(() => _locationReady = true);

      _pollTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _pollDistanceAndMaybeConfirm(),
      );
    } catch (_) {}
  }

  void _updateTarget({
    required String status,
    required bool meArrived,
    required double? lat,
    required double? lng,
  }) {
    if (!mounted) return;

    final bool changed = _targetStatus != status || _meArrived != meArrived || _targetLat != lat || _targetLng != lng;
    if (!changed) return;

    setState(() {
      _targetStatus = status;
      _meArrived = meArrived;
      _targetLat = lat;
      _targetLng = lng;

      if (meArrived) {
        _closeEnoughSince = null;
      }
    });
  }

  Future<void> _pollDistanceAndMaybeConfirm() async {
    if (!_locationReady) return;
    if (_targetLat == null || _targetLng == null) return;
    if (_targetStatus != "live") return;
    if (_meArrived) return;
    if (_autoConfirmSent) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      );

      final double distanceMeters = Geolocator.distanceBetween(
        _targetLat!,
        _targetLng!,
        position.latitude,
        position.longitude,
      );

      final DateTime now = DateTime.now();
      DateTime? closeSince = _closeEnoughSince;

      if (distanceMeters <= 50) {
        closeSince ??= now;
      } else {
        closeSince = null;
      }

      bool shouldAutoConfirm = false;
      if (closeSince != null && now.difference(closeSince) >= const Duration(minutes: 2)) {
        shouldAutoConfirm = true;
      }

      if (!mounted) return;
      setState(() {
        _currentDistanceMeters = distanceMeters;
        _closeEnoughSince = closeSince;
      });

      if (shouldAutoConfirm && !_autoConfirmSent) {
        setState(() {
          _autoConfirmSent = true;
          _autoConfirmNote = "We auto-confirmed your arrival based on your location.";
        });

        await MeetupService.instance.confirmArrival(meetupId: widget.meetupId);
      }
    } catch (_) {}
  }

  Future<void> _openMaps(double lat, double lng) async {
    final uri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng");
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  Future<void> _sendScenePhoto(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final String peerUid = user.uid == widget.aUid ? widget.bUid : widget.aUid;

    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(source: ImageSource.camera);
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final url = await ChatMediaService.instance.uploadChatImageBytes(
        chatId: widget.chatId,
        data: bytes,
        ext: "jpg",
      );

      await ChatService.instance.sendImageMessage(
        chatId: widget.chatId,
        imageUrl: url,
        caption: "",
        otherUid: peerUid,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Photo sent to chat")));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to send photo: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final User me = FirebaseAuth.instance.currentUser!;
    final String peerUid = me.uid == widget.aUid ? widget.bUid : widget.aUid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Meetup Live"),
        actions: [
          IconButton(
            tooltip: "Send scene photo to chat",
            icon: const Icon(Icons.photo_camera),
            onPressed: () => _sendScenePhoto(context),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: MeetupService.instance.watchMeetup(widget.meetupId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!.data();
          if (data == null) {
            return const Center(child: Text("Meetup not found"));
          }

          final String status = (data["status"] as String?) ?? "proposed";
          final bool aArrived = (data["aArrived"] as bool?) ?? false;
          final bool bArrived = (data["bArrived"] as bool?) ?? false;
          final bool allArrived = aArrived && bArrived;

          final double? lat = (data["lat"] as num?)?.toDouble();
          final double? lng = (data["lng"] as num?)?.toDouble();

          final int expMin = (data["expireMinutes"] as int?) ?? MeetupService.expireMinutes;
          final dynamic startedAt = data["startedAt"];

          final bool meArrived = (me.uid == widget.aUid) ? aArrived : bArrived;
          _updateTarget(status: status, meArrived: meArrived, lat: lat, lng: lng);

          if (status == "live" && !aArrived && !bArrived && startedAt is Timestamp) {
            final DateTime start = startedAt.toDate();
            final DateTime deadline = start.add(Duration(minutes: expMin));
            if (DateTime.now().isAfter(deadline)) {
              unawaited(MeetupService.instance.expireIfStale(meetupId: widget.meetupId));
            }
          }

          if (allArrived && status == "completed" && !_ratingOpened) {
            _ratingOpened = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => RatingSheet(
                  chatId: widget.chatId,
                  peerUid: peerUid,
                  meetupId: widget.meetupId,
                ),
              );
              if (context.mounted) {
                Navigator.of(context).maybePop();
              }
            });
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 8),
                    Text("Status: $status"),
                  ],
                ),
                const SizedBox(height: 12),
                if (lat != null && lng != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.place),
                      const SizedBox(width: 8),
                      Text("Location: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}"),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _openMaps(lat, lng),
                    icon: const Icon(Icons.directions),
                    label: const Text("Get directions"),
                  ),
                ],
                if (_currentDistanceMeters != null && status == "live") ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.social_distance),
                      const SizedBox(width: 8),
                      Text("You are ~${_currentDistanceMeters!.toStringAsFixed(0)} m from the meetup."),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.timer_outlined),
                    const SizedBox(width: 8),
                    Text("Auto-expire: $expMin min of no arrivals"),
                  ],
                ),
                const SizedBox(height: 8),
                if (_autoConfirmNote != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_autoConfirmNote!)),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.person_pin_circle),
                    const SizedBox(width: 8),
                    Text("You arrived: ${meArrived ? "Yes" : "No"}"),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.person_outline),
                    const SizedBox(width: 8),
                    Text("Peer arrived: ${((me.uid == widget.aUid) ? bArrived : aArrived) ? "Yes" : "No"}"),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: (status == "expired" || meArrived) ? null : () => MeetupService.instance.confirmArrival(meetupId: widget.meetupId),
                  icon: const Icon(Icons.check),
                  label: const Text("Confirm I'm here"),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
