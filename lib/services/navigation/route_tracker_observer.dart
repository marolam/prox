import "package:flutter/material.dart";

class RouteTrackerObserver extends RouteObserver<PageRoute<dynamic>> {
  final ValueNotifier<String> currentRoute = ValueNotifier<String>("");

  void _update(Route<dynamic>? route) {
    final name = route?.settings.name ?? "";
    if (name != currentRoute.value) currentRoute.value = name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _update(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _update(previousRoute);
  }
}
