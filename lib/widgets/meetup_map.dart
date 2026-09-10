import "package:flutter/material.dart";
import "package:flutter_map/flutter_map.dart";
import "package:latlong2/latlong.dart";

/// MeetupMap (OSM fallback)
/// - Always shows a watermark so we can confirm it renders even if tiles fail.
/// - Shows meetup pin + optional my-location pin.
/// NOTE: Tiles may fail to load if network/DNS/TLS is blocked; pins/watermark should still appear.
class MeetupMap extends StatefulWidget {
  final LatLng center;
  final LatLng? myLocation;
  final ValueChanged<LatLng>? onLongPress;
  final ValueChanged<LatLng>? onPinDrag;
  final ValueChanged<LatLng>? onPinDragEnd;
  final MapController? controller;
  final double zoom;

  const MeetupMap({
    super.key,
    required this.center,
    this.myLocation,
    this.onLongPress,
    this.onPinDrag,
    this.onPinDragEnd,
    this.controller,
    this.zoom = 15,
  });

  @override
  State<MeetupMap> createState() => _MeetupMapState();
}

class _MeetupMapState extends State<MeetupMap> {
  late final MapController _controller;
  late LatLng _pin;
  bool _draggingPin = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? MapController();
    _pin = widget.center;
  }

  @override
  void didUpdateWidget(covariant MeetupMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_draggingPin && oldWidget.center != widget.center) {
      _pin = widget.center;
    }
  }

  void _dragPin(DragUpdateDetails details) {
    final camera = _controller.camera;
    final pinOffset = camera.latLngToScreenOffset(_pin);
    final next = camera.screenOffsetToLatLng(pinOffset + details.delta);
    setState(() => _pin = next);
    widget.onPinDrag?.call(next);
  }

  void _finishPinDrag(DragEndDetails details) {
    setState(() => _draggingPin = false);
    widget.onPinDragEnd?.call(_pin);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final markers = <Marker>[
      Marker(
        point: _pin,
        width: 56,
        height: 56,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: widget.onPinDragEnd == null
              ? null
              : (_) => setState(() => _draggingPin = true),
          onPanUpdate: widget.onPinDragEnd == null ? null : _dragPin,
          onPanEnd: widget.onPinDragEnd == null ? null : _finishPinDrag,
          child: _Pin(
            color: const Color(0xFFF57C00),
            icon: Icons.place,
            emphasized: _draggingPin,
          ),
        ),
      ),
      if (widget.myLocation != null)
        Marker(
          point: widget.myLocation!,
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
                mapController: _controller,
                options: MapOptions(
                  initialCenter: widget.center,
                  initialZoom: widget.zoom,
                  onLongPress: widget.onLongPress == null
                      ? null
                      : (tapPos, latLng) {
                          setState(() => _pin = latLng);
                          widget.onLongPress!(latLng);
                        },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
                ),
                child: Text(
                  "${_pin.latitude.toStringAsFixed(5)}, ${_pin.longitude.toStringAsFixed(5)}",
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
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
  final bool emphasized;
  const _Pin({
    required this.color,
    required this.icon,
    this.emphasized = false,
  });

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
          border: Border.all(
              color: const Color(0xFFFFFFFF).withValues(alpha: 0.18)),
        ),
        padding: EdgeInsets.all(emphasized ? 13 : 10),
        child: Icon(icon, size: emphasized ? 22 : 18, color: Colors.white),
      ),
    );
  }
}
