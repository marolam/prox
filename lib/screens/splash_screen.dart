import "dart:math" as math;

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

enum _SplashVariant { a, b }

const _activeSplashVariant = _SplashVariant.a;

class _SplashVariantStyle {
  const _SplashVariantStyle({
    required this.backgroundStart,
    required this.backgroundEnd,
    required this.radarColor,
    required this.rippleColor,
    required this.glowColor,
    required this.taglineColor,
    required this.logoTint,
    required this.logoWidth,
    required this.radarSize,
  });

  final Color backgroundStart;
  final Color backgroundEnd;
  final Color radarColor;
  final Color rippleColor;
  final Color glowColor;
  final Color taglineColor;
  final Color logoTint;
  final double logoWidth;
  final double radarSize;
}

const _variantAStyle = _SplashVariantStyle(
  backgroundStart: Color(0xFF071126),
  backgroundEnd: Color(0xFF030913),
  radarColor: Color(0xFF73D9FF),
  rippleColor: Color(0xFF8CE8FF),
  glowColor: Color(0xFF2FAEDD),
  taglineColor: Color(0xFFD6E8F5),
  logoTint: Color(0xFFD9EEFF),
  logoWidth: 304,
  radarSize: 212,
);

const _variantBStyle = _SplashVariantStyle(
  backgroundStart: Color(0xFF08171D),
  backgroundEnd: Color(0xFF040D11),
  radarColor: Color(0xFF7DF3CF),
  rippleColor: Color(0xFFAAFFE4),
  glowColor: Color(0xFF39C8A2),
  taglineColor: Color(0xFFD8EFE5),
  logoTint: Color(0xFFE3FFF2),
  logoWidth: 312,
  radarSize: 224,
);

_SplashVariantStyle _styleFor(_SplashVariant variant) {
  switch (variant) {
    case _SplashVariant.b:
      return _variantBStyle;
    case _SplashVariant.a:
      return _variantAStyle;
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.previewMode = false});

  final bool previewMode;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _cycle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4800),
  )..repeat();

  late _SplashVariant _runtimeVariant = _activeSplashVariant;

  void _toggleVariant() {
    setState(() {
      _runtimeVariant = _runtimeVariant == _SplashVariant.a
          ? _SplashVariant.b
          : _SplashVariant.a;
    });
  }

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(_runtimeVariant);

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _toggleVariant,
        child: AnimatedBuilder(
          animation: _cycle,
          builder: (context, _) {
            final scan = _cycle.value;
            final ripple = Curves.easeOutCubic.transform(
              ((scan - 0.2) / 0.58).clamp(0.0, 1.0),
            );
            final mottoReveal = Curves.easeOut.transform(
              ((scan - 0.54) / 0.36).clamp(0.0, 1.0),
            );
            final lift = 1.8 * math.sin(scan * math.pi * 2);
            final retainedGlow = 0.3 + 0.7 * ripple;

            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[style.backgroundStart, style.backgroundEnd],
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _NebulaBackdrop(progress: scan, tint: style.radarColor),
                  _DepthParticleLayer(progress: scan, color: style.radarColor),
                  _AmbientRadarWash(progress: scan, color: style.radarColor),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 26),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Transform.translate(
                            offset: Offset(0, lift),
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.center,
                              children: <Widget>[
                                _RadarCircleLayer(
                                  progress: scan,
                                  size: style.radarSize,
                                  color: style.radarColor,
                                ),
                                IgnorePointer(
                                  child: Container(
                                    width: style.radarSize + 16,
                                    height: style.radarSize + 16,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: <BoxShadow>[
                                        BoxShadow(
                                          color: style.glowColor.withValues(
                                            alpha: 0.1 + 0.14 * retainedGlow,
                                          ),
                                          blurRadius: 84,
                                          spreadRadius: 6,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                _RippleLogoMask(
                                  progress: ripple,
                                  rippleColor: style.rippleColor,
                                  ambientColor: style.radarColor,
                                  child: ColorFiltered(
                                    colorFilter: ColorFilter.mode(
                                      style.logoTint,
                                      BlendMode.modulate,
                                    ),
                                    child: Image.asset(
                                      "img/prox-logo-new-lettering.png",
                                      width: style.logoWidth,
                                      filterQuality: FilterQuality.high,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Opacity(
                            opacity: 0.05 + (0.82 * mottoReveal),
                            child: Transform.translate(
                              offset: Offset(0, 10 * (1 - mottoReveal)),
                              child: Text(
                                "Let what you seek find you.",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.sora(
                                  color: style.taglineColor,
                                  fontSize: 15.8,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.28,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.previewMode)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: SafeArea(
                        child: FilledButton.tonalIcon(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close),
                          label: const Text("Close"),
                        ),
                      ),
                    ),
                  if (kDebugMode || widget.previewMode)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: SafeArea(
                        child: FilledButton.tonal(
                          onPressed: _toggleVariant,
                          child: Text(
                            _runtimeVariant == _SplashVariant.a
                                ? "Radar A"
                                : "Radar B",
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RippleLogoMask extends StatelessWidget {
  const _RippleLogoMask({
    required this.progress,
    required this.rippleColor,
    required this.ambientColor,
    required this.child,
  });

  final double progress;
  final Color rippleColor;
  final Color ambientColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ringPos = 0.1 + (progress * 0.78);
    final outer = (ringPos + 0.15).clamp(0.0, 1.0);
    final inner = (ringPos - 0.09).clamp(0.0, 1.0);

    return ShaderMask(
      blendMode: BlendMode.modulate,
      shaderCallback: (Rect rect) {
        return RadialGradient(
          center: Alignment.center,
          radius: 1.48,
          colors: <Color>[
            ambientColor.withValues(alpha: 0.66),
            ambientColor.withValues(alpha: 0.72),
            rippleColor.withValues(alpha: 0.6 + progress * 0.18),
            rippleColor.withValues(alpha: 0.9),
            ambientColor.withValues(alpha: 0.74),
            ambientColor.withValues(alpha: 0.64),
          ],
          stops: <double>[
            0.0,
            inner,
            ringPos,
            outer,
            (outer + 0.08).clamp(0.0, 1.0),
            1.0,
          ],
        ).createShader(rect);
      },
      child: child,
    );
  }
}

class _RadarCircleLayer extends StatelessWidget {
  const _RadarCircleLayer({
    required this.progress,
    required this.size,
    required this.color,
  });

  final double progress;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _RadarCirclePainter(progress: progress, color: color),
    );
  }
}

class _RadarCirclePainter extends CustomPainter {
  const _RadarCirclePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 7;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..color = color.withValues(alpha: 0.22);

    canvas.drawCircle(center, radius, ringPaint);
    canvas.drawCircle(center, radius * 0.68, ringPaint);
    canvas.drawCircle(center, radius * 0.38, ringPaint);

    final cross = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.19);
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      cross,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      cross,
    );

    final sweepAngle = (-math.pi / 2) + progress * math.pi * 2;
    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.3
      ..color = color.withValues(alpha: 0.76);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      sweepAngle - 0.33,
      0.66,
      false,
      sweep,
    );

    final markerRadius = radius * 0.85;
    final marker = Offset(
      center.dx + math.cos(sweepAngle) * markerRadius,
      center.dy + math.sin(sweepAngle) * markerRadius,
    );

    final xPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.9
      ..color = color.withValues(alpha: 0.9);

    const half = 6.8;
    canvas.drawLine(
      Offset(marker.dx - half, marker.dy - half),
      Offset(marker.dx + half, marker.dy + half),
      xPaint,
    );
    canvas.drawLine(
      Offset(marker.dx + half, marker.dy - half),
      Offset(marker.dx - half, marker.dy + half),
      xPaint,
    );

    final ping = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.22 + 0.24 * math.sin(progress * math.pi * 2).abs());
    canvas.drawCircle(marker, 3.2, ping);
  }

  @override
  bool shouldRepaint(covariant _RadarCirclePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _NebulaBackdrop extends StatelessWidget {
  const _NebulaBackdrop({required this.progress, required this.tint});

  final double progress;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final driftA = math.sin(progress * math.pi * 2) * 18;
    final driftB = math.cos(progress * math.pi * 2) * 14;

    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -130 + driftA,
            left: -140,
            child: _softBlob(size: 360, color: tint.withValues(alpha: 0.1)),
          ),
          Positioned(
            right: -150,
            bottom: 40 + driftB,
            child: _softBlob(size: 340, color: tint.withValues(alpha: 0.08)),
          ),
          Positioned(
            left: -80,
            right: -80,
            top: 250,
            child: _softBlob(size: 520, color: tint.withValues(alpha: 0.06)),
          ),
        ],
      ),
    );
  }

  Widget _softBlob({required double size, required Color color}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _DepthParticleLayer extends StatelessWidget {
  const _DepthParticleLayer({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _DepthParticlePainter(progress: progress, color: color),
      ),
    );
  }
}

class _DepthParticlePainter extends CustomPainter {
  const _DepthParticlePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(12);
    for (var i = 0; i < 110; i++) {
      final x = rnd.nextDouble() * size.width;
      final yBase = rnd.nextDouble() * size.height;
      final drift = math.sin((progress * math.pi * 2) + i * 0.7) * 7;
      final y = yBase + drift;
      final radius = 0.8 + rnd.nextDouble() * 2.6;
      final alpha = 0.02 + (rnd.nextDouble() * 0.08);
      final paint = Paint()..color = color.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DepthParticlePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _AmbientRadarWash extends StatelessWidget {
  const _AmbientRadarWash({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _AmbientRadarWashPainter(progress: progress, color: color),
      ),
    );
  }
}

class _AmbientRadarWashPainter extends CustomPainter {
  const _AmbientRadarWashPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 30);
    final maxRadius = math.max(size.width, size.height) * 0.74;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    for (var i = 0; i < 3; i++) {
      final shifted = (progress + (i * 0.23)) % 1;
      final radius = maxRadius * (0.2 + shifted * 0.72);
      ringPaint.color = color.withValues(alpha: 0.05 + (1 - shifted) * 0.07);
      canvas.drawCircle(center, radius, ringPaint);
    }

    final sweepAngle = -math.pi / 2 + progress * math.pi * 2;
    final rect = Rect.fromCircle(center: center, radius: maxRadius);
    final sweepPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = SweepGradient(
        startAngle: sweepAngle - 0.22,
        endAngle: sweepAngle + 0.22,
        colors: <Color>[
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.07),
          color.withValues(alpha: 0),
        ],
      ).createShader(rect);

    canvas.drawCircle(center, maxRadius, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant _AmbientRadarWashPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
