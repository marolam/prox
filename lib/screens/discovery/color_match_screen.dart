import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:prox/models/color_match_models.dart";
import "package:screen_brightness/screen_brightness.dart";
import "package:wakelock_plus/wakelock_plus.dart";

class ColorMatchScreen extends StatefulWidget {
  const ColorMatchScreen({
    super.key,
    this.initialColor = MatchColor.red,
    this.meetupId = "",
    this.onDismiss,
  });

  final MatchColor initialColor;
  final String meetupId;
  final VoidCallback? onDismiss;

  @override
  State<ColorMatchScreen> createState() => _ColorMatchScreenState();
}

class _ColorMatchScreenState extends State<ColorMatchScreen> {
  late final MatchColor _selected = _colorForMeetup(widget.meetupId);

  MatchColor _colorForMeetup(String meetupId) {
    final normalized = meetupId.trim();
    if (normalized.isEmpty) return widget.initialColor;
    var hash = 0;
    for (final unit in normalized.codeUnits) {
      hash = ((hash * 31) + unit) & 0x7fffffff;
    }
    return MatchColor.values[hash % MatchColor.values.length];
  }

  Color get _color => switch (_selected) {
        MatchColor.red => const Color(0xFFFF1F2D),
        MatchColor.green => const Color(0xFF00E676),
        MatchColor.blue => const Color(0xFF1687FF),
        MatchColor.yellow => const Color(0xFFFFE600),
      };

  Color get _foreground =>
      _selected == MatchColor.yellow || _selected == MatchColor.green
          ? Colors.black
          : Colors.white;

  @override
  void initState() {
    super.initState();
    _enableBeaconDisplay();
  }

  Future<void> _enableBeaconDisplay() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(1);
    } catch (_) {}
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  Future<void> _restoreDisplay() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {}
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    _restoreDisplay();
    widget.onDismiss?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      child: Scaffold(
        backgroundColor: _color,
        body: SizedBox.expand(
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.waving_hand, size: 88, color: _foreground),
                    const SizedBox(height: 18),
                    Text(
                      "HOLD UP YOUR PHONE",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _foreground,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Both phones show the same meetup color",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _foreground.withValues(alpha: 0.82),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 18,
                right: 18,
                child: IconButton.filled(
                  tooltip: "Close",
                  style: IconButton.styleFrom(
                    backgroundColor: _foreground.withValues(alpha: 0.18),
                    foregroundColor: _foreground,
                  ),
                  onPressed: () => Navigator.of(context).pop(_selected),
                  icon: const Icon(Icons.close),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 28,
                child: Text(
                  "Maximum brightness is active. Keep this screen raised until you find each other.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _foreground.withValues(alpha: 0.82),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
