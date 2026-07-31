import "package:flutter/material.dart";

class BusinessIntroSheet {
  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            "Business discovery helps route high-intent local requests. You can switch this any time.",
          ),
        ),
      ),
    );
  }
}
