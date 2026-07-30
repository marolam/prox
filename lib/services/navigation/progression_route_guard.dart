import "package:flutter/material.dart";

import "package:prox/home/home_root_shell.dart";
import "package:prox/services/meetup_focus_lock_service.dart";
import "package:prox/services/matching/match_dashboard_session_service.dart";

class ProgressionRouteGuard {
  static const Set<String> _allowedRoutes = <String>{
    "/",
    "/auth",
    "/home",
    "/nearby",
    "/matches",
    "/chat",
    "/meetup_plan",
    "/meetup_live",
    "/rate",
  };

  static const Set<String> _allowedDuringMeetupFocusLock = <String>{
    "/",
    "/auth",
    "/home",
    "/chat",
    "/meetup_plan",
    "/meetup_live",
    "/rate",
  };

  static bool shouldBlockRoute(String routeName) {
    if (MeetupFocusLockService.instance.isLocked) {
      if (!_allowedDuringMeetupFocusLock.contains(routeName)) return true;
    }
    if (_allowedRoutes.contains(routeName)) return false;
    return MatchDashboardSessionService.instance.hasActiveSession;
  }

  static Widget wrap({
    required String routeName,
    required Widget child,
  }) {
    if (!shouldBlockRoute(routeName)) return child;
    return const HomeRootShell();
  }

  static Route<T> guardedMaterialRoute<T>({
    required String routeName,
    required WidgetBuilder builder,
  }) {
    return MaterialPageRoute<T>(
      settings: RouteSettings(name: routeName),
      builder: (context) => wrap(
        routeName: routeName,
        child: builder(context),
      ),
    );
  }
}