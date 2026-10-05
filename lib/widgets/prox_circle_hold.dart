import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Owns a pointer inside the circle so a parent scroll view cannot cancel a hold.
class ProxCircleHold extends StatefulWidget {
  const ProxCircleHold({
    super.key,
    required this.child,
    required this.onHold,
    required this.onProgress,
    this.onTap,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onHold;
  final ValueChanged<double> onProgress;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  State<ProxCircleHold> createState() => _ProxCircleHoldState();
}

class _ProxCircleHoldState extends State<ProxCircleHold>
    with WidgetsBindingObserver {
  Timer? _timer;
  Timer? _completion;
  int? _pointer;
  bool _completed = false;
  bool _cancelled = false;

  bool _inside(Offset position, {double tolerance = 0}) {
    final size = context.size;
    if (size == null) return false;
    return (position - size.center(Offset.zero)).distance <=
        size.shortestSide / 2 + tolerance;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null || !_inside(event.localPosition)) return;
    _pointer = event.pointer;
    _completed = false;
    _cancelled = false;
    if (!widget.enabled) return;
    _timer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      widget.onProgress((timer.tick * 16 / 3000).clamp(0.0, 1.0));
    });
    _completion = Timer(const Duration(seconds: 3), () {
      _timer?.cancel();
      _completed = true;
      widget.onProgress(1);
      widget.onHold();
    });
  }

  void _event(PointerEvent event) {
    if (event is PointerDownEvent) {
      _down(event);
    } else if (event.pointer == _pointer) {
      if (event is PointerMoveEvent &&
          !_inside(event.localPosition, tolerance: 8)) {
        _cancelled = true;
        _stop();
      } else if (event is PointerUpEvent || event is PointerCancelEvent) {
        final tapped = event is PointerUpEvent && !_completed && !_cancelled;
        _pointer = null;
        _stop();
        if (tapped) widget.onTap?.call();
      }
    }
  }

  void _stop() {
    _timer?.cancel();
    _completion?.cancel();
    _timer = null;
    widget.onProgress(0);
  }

  @override
  void didUpdateWidget(covariant ProxCircleHold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _timer?.cancel();
      _completion?.cancel();
      _cancelled = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _cancelled = true;
      _stop();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _completion?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: {
      _CirclePointerRecognizer:
          GestureRecognizerFactoryWithHandlers<_CirclePointerRecognizer>(
            _CirclePointerRecognizer.new,
            (recognizer) => recognizer
              ..inside = _inside
              ..onEvent = _event,
          ),
    },
    child: widget.child,
  );
}

class _CirclePointerRecognizer extends OneSequenceGestureRecognizer {
  late bool Function(Offset) inside;
  late void Function(PointerEvent) onEvent;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!inside(event.localPosition)) return;
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
    onEvent(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    onEvent(event);
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'Prox circle hold';
}
