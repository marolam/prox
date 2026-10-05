import 'package:flutter/material.dart';

/// Like [showDialog], but returns after its exit transition and widget removal.
/// Controllers created for the dialog can safely be disposed after this future.
Future<T?> showDialogUntilRemoved<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool fullscreenDialog = false,
  bool? requestFocus,
  AnimationStyle? animationStyle,
}) async {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    barrierColor:
        barrierColor ??
        DialogTheme.of(context).barrierColor ??
        Theme.of(context).dialogTheme.barrierColor ??
        Colors.black54,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    settings: routeSettings,
    anchorPoint: anchorPoint,
    traversalEdgeBehavior:
        traversalEdgeBehavior ?? TraversalEdgeBehavior.closedLoop,
    fullscreenDialog: fullscreenDialog,
    requestFocus: requestFocus,
    animationStyle: animationStyle,
  );
  final result = await navigator.push<T>(route);
  await route.completed;
  return result;
}
