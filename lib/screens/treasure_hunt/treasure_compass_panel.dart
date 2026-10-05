import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/services/location_privacy_service.dart';
import 'package:prox/services/matching/treasure_compass_service.dart';
import 'package:prox/services/presence_writer.dart';
import 'hunt_compass.dart';

class TreasureCompassPanel extends StatefulWidget {
  const TreasureCompassPanel({super.key, required this.discovery});
  final MatchDiscoverySettings discovery;
  @override
  State<TreasureCompassPanel> createState() => _TreasureCompassPanelState();
}

class _TreasureCompassPanelState extends State<TreasureCompassPanel> {
  TreasureAreaSnapshot? _snapshot;
  GeoPoint? _position;
  String? _error;
  bool _loading = false;
  Timer? _tick;
  StreamSubscription<MotionSnapshot>? _motion;
  DateTime? _positionAt;

  @override
  void initState() {
    super.initState();
    LocationPrivacyService.instance.addListener(_privacyChanged);
    _motion = PresenceWriter.instance.motionStream.listen((sample) {
      if (!mounted ||
          !LocationPrivacyService.instance.mayReadLocation ||
          DateTime.now().difference(sample.ts) > const Duration(minutes: 2))
        return;
      setState(() {
        _position = GeoPoint(sample.lat, sample.lng);
        _positionAt = sample.ts;
      });
    });
    // Age the display locally; this timer never queries other users.
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  void _privacyChanged() {
    if (!LocationPrivacyService.instance.locationEnabled) {
      TreasureCompassService.instance.clearSession();
      setState(() {
        _snapshot = null;
        _position = null;
        _error = 'Enable location to use the Matching Compass.';
      });
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await TreasureCompassService.instance.snapshot(
        widget.discovery,
      );
      if (!mounted || !LocationPrivacyService.instance.locationEnabled) return;
      setState(() {
        _snapshot = snapshot;
        _position = snapshot.origin;
        _positionAt = snapshot.capturedAt;
      });
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Could not load an area snapshot. Check location and your connection, then retry.',
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _motion?.cancel();
    _tick?.cancel();
    LocationPrivacyService.instance.removeListener(_privacyChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final now = DateTime.now();
    final expired = snapshot?.isExpired(now) ?? true;
    final area = snapshot?.area;
    final origin = _position ?? snapshot?.origin;
    final locationFresh =
        _positionAt != null &&
        now.difference(_positionAt!) <= const Duration(minutes: 2);
    return SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(60),
              child: CircularProgressIndicator(),
            )
          else if (_error != null)
            Text(_error!, textAlign: TextAlign.center)
          else if (expired)
            const Text(
              'This area snapshot has expired. Refresh for a new clue.',
              textAlign: TextAlign.center,
            )
          else if (area == null)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No promising area in this snapshot yet. Try a wider Treasure radius or refresh in a few minutes.',
                textAlign: TextAlign.center,
              ),
            )
          else if (!locationFresh)
            const Text(
              'Waiting for a recent location to update direction and warmth.',
              textAlign: TextAlign.center,
            )
          else if (origin != null)
            HuntCompass(
              bearingDegrees: TreasureAreaSnapshot.bearing(origin, area),
              distanceMiles: TreasureAreaSnapshot.distanceMiles(origin, area),
            ),
          const SizedBox(height: 12),
          const Text(
            'A general area worth exploring, based on your matching criteria. People may move; matches are not guaranteed. When closer, switch to Normal and hold the circle to match.',
            textAlign: TextAlign.center,
          ),
          if (snapshot != null && !expired) ...[
            const SizedBox(height: 6),
            Text(
              'Area snapshot: ${now.difference(snapshot.capturedAt).inMinutes.clamp(0, 5)} min ago. Refresh available after 5 minutes.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          TextButton.icon(
            onPressed: !_loading && (expired || _error != null) ? _load : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh area snapshot'),
          ),
        ],
      ),
    );
  }
}
