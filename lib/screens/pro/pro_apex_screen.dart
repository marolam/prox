import "dart:async";
import "dart:math" as math;

import "package:flutter/material.dart";

import "package:prox/models/pro_mode_models.dart";

class ProApexScreen extends StatefulWidget {
  const ProApexScreen({super.key});

  @override
  State<ProApexScreen> createState() => _ProApexScreenState();
}

class _ProApexScreenState extends State<ProApexScreen> {
  static const Duration _holdDuration = Duration(seconds: 3);

  List<ProCircleConfig> _circles = const <ProCircleConfig>[
    ProCircleConfig(
      id: "urgent_service",
      label: "Immediate",
      matchType: "Ready-now requests",
      keywords: <String>["repair", "delivery", "help now"],
    ),
    ProCircleConfig(
      id: "quotes",
      label: "Quotes",
      matchType: "Terms and price discovery",
      keywords: <String>["estimate", "quote", "consult"],
    ),
    ProCircleConfig(
      id: "premium",
      label: "Priority",
      matchType: "High-intent premium leads",
      keywords: <String>["same day", "premium", "licensed"],
    ),
  ];
  String? _holdingCircleId;
  Timer? _holdTimer;
  bool _hasActiveLead = false;
  DateTime? _pausedUntil;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _startHold(String circleId) {
    _holdTimer?.cancel();
    setState(() => _holdingCircleId = circleId);
    _holdTimer = Timer(_holdDuration, () {
      if (!mounted) return;
      setState(() {
        _circles = ProApexPolicy.toggleCircle(
          circles: _circles,
          circleId: circleId,
          hasActiveLead: _hasActiveLead,
        );
        _holdingCircleId = null;
      });
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    if (_holdingCircleId != null) {
      setState(() => _holdingCircleId = null);
    }
  }

  void _toggleLeadLock() {
    setState(() {
      _hasActiveLead = !_hasActiveLead;
      if (_hasActiveLead) {
        _circles = _circles
            .map((circle) => circle.copyWith(status: ProCircleStatus.off))
            .toList(growable: false);
      }
    });
  }

  void _applyOneHourPause() {
    setState(() {
      _pausedUntil = DateTime.now().add(const Duration(hours: 1));
      _circles = _circles
          .map((circle) => circle.copyWith(status: ProCircleStatus.off))
          .toList(growable: false);
    });
  }

  Future<void> _editKeywords(ProCircleConfig circle) async {
    final controller = TextEditingController(text: circle.keywords.join(", "));
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("${circle.label} keywords"),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: "service, product, skill",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () {
                final keywords = controller.text
                    .split(",")
                    .map((keyword) => keyword.trim())
                    .where((keyword) => keyword.isNotEmpty)
                    .toList(growable: false);
                Navigator.of(context).pop(keywords);
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result == null) return;
    setState(() {
      _circles = ProApexPolicy.setKeywords(
        circles: _circles,
        circleId: circle.id,
        keywords: result,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final canReceive = ProApexPolicy.canReceiveMatches(
      circles: _circles,
      hasActiveLead: _hasActiveLead,
      pausedUntil: _pausedUntil,
    );
    final activeCount = _circles.where((circle) => circle.isActive).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Pro Apex"),
        actions: [
          IconButton(
            tooltip:
                _hasActiveLead ? "Clear active lead" : "Simulate lead lock",
            onPressed: _toggleLeadLock,
            icon: Icon(_hasActiveLead
                ? Icons.lock_open_outlined
                : Icons.lock_clock_outlined),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.surface,
              Color.alphaBlend(cs.primary.withValues(alpha: 0.08), cs.surface),
              cs.surface,
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _ApexGauge(
              activeCount: activeCount,
              canReceive: canReceive,
              locked: _hasActiveLead,
            ),
            const SizedBox(height: 14),
            _StatusDeck(
              canReceive: canReceive,
              activeCount: activeCount,
              hasActiveLead: _hasActiveLead,
              pausedUntil: _pausedUntil,
              onPause: _applyOneHourPause,
            ),
            const SizedBox(height: 14),
            for (final circle in _circles) ...[
              _ProCircleCard(
                circle: circle,
                holding: _holdingCircleId == circle.id,
                blocked: _hasActiveLead,
                onHoldStart: () => _startHold(circle.id),
                onHoldCancel: _cancelHold,
                onEditKeywords: () => _editKeywords(circle),
              ),
              const SizedBox(height: 12),
            ],
            _PolicyPanel(colorScheme: cs),
          ],
        ),
      ),
    );
  }
}

class _ApexGauge extends StatelessWidget {
  const _ApexGauge({
    required this.activeCount,
    required this.canReceive,
    required this.locked,
  });

  final int activeCount;
  final bool canReceive;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CustomPaint(
            size: const Size(118, 88),
            painter: _RpmGaugePainter(
              color: canReceive ? cs.primary : cs.outline,
              activeRatio: activeCount / 3,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  locked
                      ? "Lead in progress"
                      : (canReceive ? "Ready for leads" : "Matching off"),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Pro uses immediate-intent signals from Prox to route live requests into focused circles.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RpmGaugePainter extends CustomPainter {
  const _RpmGaugePainter({required this.color, required this.activeRatio});

  final Color color;
  final double activeRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.92);
    final radius = size.width * 0.44;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 9
      ..color = color.withValues(alpha: 0.22);
    final sweep = math.pi * activeRatio.clamp(0, 1);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi,
      false,
      base,
    );
    final active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 9
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      sweep,
      false,
      active,
    );
    final needleAngle = math.pi + sweep;
    final needleEnd = Offset(
      center.dx + math.cos(needleAngle) * radius * 0.78,
      center.dy + math.sin(needleAngle) * radius * 0.78,
    );
    final needle = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawLine(center, needleEnd, needle);
    canvas.drawCircle(center, 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _RpmGaugePainter oldDelegate) {
    return color != oldDelegate.color || activeRatio != oldDelegate.activeRatio;
  }
}

class _StatusDeck extends StatelessWidget {
  const _StatusDeck({
    required this.canReceive,
    required this.activeCount,
    required this.hasActiveLead,
    required this.pausedUntil,
    required this.onPause,
  });

  final bool canReceive;
  final int activeCount;
  final bool hasActiveLead;
  final DateTime? pausedUntil;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final paused = pausedUntil != null && pausedUntil!.isAfter(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(
                  icon: Icons.speed_outlined, label: "$activeCount active"),
              _StatusChip(
                icon:
                    canReceive ? Icons.flash_on_outlined : Icons.pause_outlined,
                label: canReceive ? "Accepting" : "Standing by",
              ),
              _StatusChip(
                icon: Icons.verified_user_outlined,
                label: "Strict trust",
              ),
            ],
          ),
          if (hasActiveLead || paused) ...[
            const SizedBox(height: 10),
            Text(
              hasActiveLead
                  ? "A matched lead is active. Apex matching stays off until the lead is completed or cancelled."
                  : "Lead matching is paused for the one-hour no-accept cooldown.",
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onPause,
            icon: const Icon(Icons.timer_off_outlined),
            label: const Text("Apply 1h no-accept pause"),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _ProCircleCard extends StatelessWidget {
  const _ProCircleCard({
    required this.circle,
    required this.holding,
    required this.blocked,
    required this.onHoldStart,
    required this.onHoldCancel,
    required this.onEditKeywords,
  });

  final ProCircleConfig circle;
  final bool holding;
  final bool blocked;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldCancel;
  final VoidCallback onEditKeywords;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final active = circle.isActive;
    final accent = active ? cs.primary : cs.outline;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: active
            ? cs.primaryContainer.withValues(alpha: 0.45)
            : cs.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: accent.withValues(alpha: active ? 0.55 : 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPressStart: (_) => onHoldStart(),
            onLongPressEnd: (_) => onHoldCancel(),
            onLongPressCancel: onHoldCancel,
            child: SizedBox.square(
              dimension: 92,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: accent, width: active ? 5 : 2),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: cs.primary.withValues(alpha: 0.28),
                                blurRadius: 18,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  if (holding)
                    CircularProgressIndicator(
                      strokeWidth: 4,
                      color: cs.primary,
                    ),
                  Icon(
                    active ? Icons.power_settings_new : Icons.circle_outlined,
                    color: accent,
                    size: 34,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        circle.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      active ? "Active" : "Off",
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: active ? cs.primary : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  blocked ? "Blocked by active lead" : circle.matchType,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: blocked ? cs.error : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: circle.keywords
                      .map(
                        (keyword) => Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(keyword),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onEditKeywords,
                  icon: const Icon(Icons.tune_outlined),
                  label: const Text("Assign keywords"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyPanel extends StatelessWidget {
  const _PolicyPanel({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Pro responsibility",
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            "Pro is a privilege: one warning for negative customer experiences, then Pro suspension. Declining or ignoring a lead pauses matching for 1 hour.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
