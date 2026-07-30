import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter/material.dart";
import "package:flutter_map/flutter_map.dart";
import "package:geolocator/geolocator.dart";
import "package:latlong2/latlong.dart";

import "package:prox/dev/dev_location_pin_lab_service.dart";
import "package:prox/dev/dev_user_simulator_service.dart";

class DevLocationPinToolScreen extends StatefulWidget {
  const DevLocationPinToolScreen({super.key});

  @override
  State<DevLocationPinToolScreen> createState() =>
      _DevLocationPinToolScreenState();
}

class _DevLocationPinToolScreenState extends State<DevLocationPinToolScreen> {
  final MapController _mapController = MapController();

  LatLng _center = const LatLng(37.7749, -122.4194);
  LatLng? _draftPin;
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await DevLocationPinLabService.instance.ensureLoaded();

    final selfPin = DevLocationPinLabService.instance
        .pinFor(DevLocationPinKind.selfDemoLocation);
    final treasurePin = DevLocationPinLabService.instance
        .pinFor(DevLocationPinKind.treasureTarget);
    final candidate = selfPin ?? treasurePin;
    if (candidate != null) {
      _center = LatLng(candidate.lat, candidate.lng);
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 3),
          distanceFilter: 25,
        ),
      );
      _center = LatLng(pos.latitude, pos.longitude);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _booting = false;
    });
  }

  Future<void> _assign(DevLocationPinKind kind) async {
    final point = _draftPin;
    if (point == null) return;

    await DevLocationPinLabService.instance.setPin(
      kind: kind,
      lat: point.latitude,
      lng: point.longitude,
    );

    if (kind == DevLocationPinKind.simulatedNearbyUser) {
      DevUserSimulatorService.instance.spawnPreset(
        1,
        around: GeoPoint(point.latitude, point.longitude),
      );
    }

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Assigned pin to ${_label(kind)}.")),
    );
  }

  Future<void> _clear(DevLocationPinKind kind) async {
    await DevLocationPinLabService.instance.clearPin(kind);
    if (kind == DevLocationPinKind.simulatedNearbyUser) {
      DevUserSimulatorService.instance.stop();
    }
    if (!mounted) return;
    setState(() {});
  }

  Color _colorFor(DevLocationPinKind kind) {
    switch (kind) {
      case DevLocationPinKind.selfDemoLocation:
        return const Color(0xFF00897B);
      case DevLocationPinKind.simulatedNearbyUser:
        return const Color(0xFFD84315);
      case DevLocationPinKind.meetupLocation:
        return const Color(0xFF2E7D32);
      case DevLocationPinKind.treasureTarget:
        return const Color(0xFFF9A825);
      case DevLocationPinKind.generic:
        return const Color(0xFF1565C0);
    }
  }

  String _label(DevLocationPinKind kind) {
    switch (kind) {
      case DevLocationPinKind.selfDemoLocation:
        return "Self location";
      case DevLocationPinKind.simulatedNearbyUser:
        return "Simulated nearby user";
      case DevLocationPinKind.meetupLocation:
        return "Meetup location";
      case DevLocationPinKind.treasureTarget:
        return "Treasure target";
      case DevLocationPinKind.generic:
        return "Generic bookmark";
    }
  }

  @override
  Widget build(BuildContext context) {
    final pins = DevLocationPinLabService.instance.pins;

    final markers = <Marker>[
      for (final entry in pins.entries)
        Marker(
          point: LatLng(entry.value.lat, entry.value.lng),
          width: 44,
          height: 44,
          child: _PinDot(color: _colorFor(entry.key), icon: Icons.place),
        ),
      if (_draftPin != null)
        Marker(
          point: _draftPin!,
          width: 50,
          height: 50,
          child: const _PinDot(
              color: Color(0xFF6A1B9A), icon: Icons.add_location_alt),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Dev Pin Drop Tool")),
      body: _booting
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: 14,
                      onTap: (tapPos, latLng) {
                        setState(() {
                          _draftPin = latLng;
                        });
                      },
                      onLongPress: (tapPos, latLng) {
                        setState(() {
                          _draftPin = latLng;
                        });
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                        userAgentPackageName: "com.prox.app",
                        maxZoom: 19,
                      ),
                      MarkerLayer(markers: markers),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      top: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withValues(alpha: 0.2)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _draftPin == null
                            ? "Tap map to place a pin"
                            : "Draft pin: ${_draftPin!.latitude.toStringAsFixed(5)}, ${_draftPin!.longitude.toStringAsFixed(5)}",
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _draftPin == null
                                ? null
                                : () => _assign(
                                    DevLocationPinKind.simulatedNearbyUser),
                            icon: const Icon(Icons.person_pin_circle_outlined),
                            label: const Text("Assign: Sim User"),
                          ),
                          FilledButton.icon(
                            onPressed: _draftPin == null
                                ? null
                                : () =>
                                    _assign(DevLocationPinKind.meetupLocation),
                            icon: const Icon(Icons.handshake_outlined),
                            label: const Text("Assign: Meetup"),
                          ),
                          FilledButton.icon(
                            onPressed: _draftPin == null
                                ? null
                                : () =>
                                    _assign(DevLocationPinKind.treasureTarget),
                            icon: const Icon(Icons.radar_outlined),
                            label: const Text("Assign: Treasure"),
                          ),
                          OutlinedButton.icon(
                            onPressed: _draftPin == null
                                ? null
                                : () => _assign(DevLocationPinKind.generic),
                            icon: const Icon(Icons.bookmark_add_outlined),
                            label: const Text("Assign: Bookmark"),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final kind in DevLocationPinKind.values)
                            OutlinedButton(
                              onPressed: pins.containsKey(kind)
                                  ? () => _clear(kind)
                                  : null,
                              child: Text("Clear ${_label(kind)}"),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _PinDot extends StatelessWidget {
  const _PinDot({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.8), width: 2),
          boxShadow: const [
            BoxShadow(
              blurRadius: 10,
              offset: Offset(0, 4),
              color: Color(0x55000000),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
