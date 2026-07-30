import "package:flutter/material.dart";

void safeShowSnackBar(BuildContext context, Object messageOrSnackBar) {
  if (!context.mounted) return;

  final SnackBar snack = messageOrSnackBar is SnackBar
      ? messageOrSnackBar
      : SnackBar(content: Text(messageOrSnackBar.toString()));

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(snack);
}

void safeSnack(BuildContext context, Object messageOrSnackBar) {
  safeShowSnackBar(context, messageOrSnackBar);
}
