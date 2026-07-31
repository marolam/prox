import "package:flutter/material.dart";
import "package:prox/services/build_info_service.dart";

class BuildInfoBadge extends StatelessWidget {
  const BuildInfoBadge({
    super.key,
    this.showBuiltAt = false,
    this.center = true,
  });

  final bool showBuiltAt;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final info = BuildInfoService.instance.info;
    final label = showBuiltAt
        ? "${info.shortLabel} · ${info.builtAt.millisecondsSinceEpoch <= 0 ? "unknown" : info.builtAt.toLocal()}"
        : info.shortLabel;
    return Align(
      alignment: center ? Alignment.center : Alignment.centerLeft,
      child: Chip(label: Text(label)),
    );
  }
}