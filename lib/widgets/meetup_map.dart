import "package:flutter/material.dart";
import "package:flutter_map/flutter_map.dart";
import "package:latlong2/latlong.dart";

/// MeetupMap (OSM fallback)
/// - Always shows a watermark so we can confirm it renders even if tiles fail.
/// - Shows meetup pin + optional my-location pin.
/// NOTE: Tiles may fail to load if network/DNS/TLS is blocked; pins/watermark should still appear.
class MeetupMap extends StatelessWidget {
  final LatLng center;
  final LatLng? myLocation;
  final ValueChanged<LatLng>? onLongPress;
  final MapController? controller;
  final double zoom;

  const MeetupMap({
    super.key,
    required this.center,
    this.myLocation,
    this.onLongPress,
    this.controller,
    this.zoom = 15,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final markers = <Marker>[
      Marker(
        point: center,
        width: 46,
        height: 46,
        child: const _Pin(color: Color(0xFFF57C00), icon: Icons.place),
      ),
      if (myLocation != null)
        Marker(
          point: myLocation!,
          width: 42,
          height: 42,
          child: const _Pin(color: Color(0xFF2E7D32), icon: Icons.my_location),
        ),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          // Background ensures we see *something* even if tiles are blank.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: cs.surfaceContainerHighest),
              child: FlutterMap(
                mapController: controller,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: zoom,
                  onLongPress: onLongPress == null
                      ? null
                      : (tapPos, latLng) => onLongPress!(latLng),
                ),
                children: [
                  TileLayer(
                    urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                    userAgentPackageName: "com.prox.app",
                    maxZoom: 19,
                    retinaMode: true,
                  ),
                  MarkerLayer(markers: markers),
                ],
              ),
            ),
          ),

          // Watermark to prove rendering even if tiles fail.
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: 0.08,
                  child: Text(
                    "MAP ACTIVE",
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Tiny debug readout (center coords)
          Positioned(
            left: 10,
            bottom: 10,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
                ),
                child: Text(
                  "${center.latitude.toStringAsFixed(5)}, ${center.longitude.toStringAsFixed(5)}",
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  final Color color;
  final IconData icon;
  const _Pin({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              blurRadius: 10,
              offset: Offset(0, 4),
              color: Color(0x66000000),
            ),
          ],
          border: Border.all(color: const Color(0xFFFFFFFF).withValues(alpha: 0.18)),
        ),
        padding: const EdgeInsets.all(10),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}
