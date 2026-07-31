import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";

class ProxLogoMark extends StatelessWidget {
  const ProxLogoMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SvgPicture.asset(
          "img/prox-logo.svg",
          width: size,
          height: size,
        ),
      ),
    );
  }
}