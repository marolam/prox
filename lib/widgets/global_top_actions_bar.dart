import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:prox/models/notification_item.dart";
import "package:prox/screens/help/context_help_screen.dart";
import "package:prox/services/help/context_help_service.dart";
import "package:prox/services/navigation/route_tracker_observer.dart";
import "package:prox/services/notification_feed_service.dart";

bool _canNavigate(GlobalKey<NavigatorState> key) {
  return key.currentState != null && key.currentContext != null;
}

class GlobalTopActionsBar extends StatelessWidget {
  const GlobalTopActionsBar({
    super.key,
    required this.routeTracker,
    required this.navigatorKey,
  });

  final RouteTrackerObserver routeTracker;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const hiddenRoutes = <String>{"/", "/auth", "/onboarding", "/profile_setup"};
    const hiddenContexts = <String>{"home:nearby"};
    const hiddenContextPrefixes = <String>{"auth:", "onboarding:", "splash:"};

    return ValueListenableBuilder<String>(
      valueListenable: routeTracker.currentRoute,
      builder: (context, routeName, _) {
        return ValueListenableBuilder<String?>(
          valueListenable: ContextHelpService.instance.contextKey,
          builder: (context, contextKey, __) {
            final normalizedContext = (contextKey ?? "").trim().toLowerCase();
            final bool hiddenByRoute = hiddenRoutes.contains(routeName);
            final bool hiddenByContext = hiddenContexts.contains(normalizedContext) ||
                hiddenContextPrefixes.any(
                  (prefix) => normalizedContext.startsWith(prefix),
                );
            final bool visibleByRoute =
                routeName.trim().isNotEmpty && !hiddenByRoute;
            final bool visibleByContext =
                normalizedContext.isNotEmpty && !hiddenByContext;

            if (hiddenByContext || (!visibleByRoute && !visibleByContext)) {
              return const SizedBox.shrink();
            }

            return Positioned(
              top: MediaQuery.of(context).padding.top + 6,
              right: 10,
              child: Material(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(22),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _WalletIcon(
                        routeTracker: routeTracker,
                        navigatorKey: navigatorKey,
                      ),
                      _InboxIcon(
                        routeTracker: routeTracker,
                        navigatorKey: navigatorKey,
                      ),
                      _NotificationsIcon(
                        routeTracker: routeTracker,
                        navigatorKey: navigatorKey,
                      ),
                      IconButton(
                        tooltip: "How to use this page",
                        onPressed: () {
                          final nav = navigatorKey.currentState;
                          if (nav == null || !_canNavigate(navigatorKey)) return;
                          final key = ContextHelpService.instance.contextKey.value;
                          try {
                            nav.push(
                              MaterialPageRoute<void>(
                                builder: (_) => ContextHelpScreen(
                                  routeName: routeName,
                                  contextKey: key,
                                ),
                              ),
                            );
                          } catch (_) {
                            // Ignore transient navigation failures during route churn.
                          }
                        },
                        icon: const Icon(Icons.help_outline),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _WalletIcon extends StatelessWidget {
  const _WalletIcon({
    required this.routeTracker,
    required this.navigatorKey,
  });

  final RouteTrackerObserver routeTracker;
  final GlobalKey<NavigatorState> navigatorKey;

  void _openWallet() {
    final route = routeTracker.currentRoute.value;
    if (route == "/store") return;
    if (!_canNavigate(navigatorKey)) return;
    try {
      navigatorKey.currentState?.pushNamed("/store");
    } catch (_) {
      // Ignore transient navigation failures during route churn.
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: "Wallet",
      onPressed: _openWallet,
      icon: const Icon(Icons.wallet_outlined),
    );
  }
}

class _InboxIcon extends StatelessWidget {
  const _InboxIcon({
    required this.routeTracker,
    required this.navigatorKey,
  });

  final RouteTrackerObserver routeTracker;
  final GlobalKey<NavigatorState> navigatorKey;

  void _openInbox() {
    final route = routeTracker.currentRoute.value;
    if (route == "/inbox") return;
    if (!_canNavigate(navigatorKey)) return;
    try {
      navigatorKey.currentState?.pushNamed("/inbox");
    } catch (_) {
      // Ignore transient navigation failures during route churn.
    }
  }

  @override
  Widget build(BuildContext context) {
    FirebaseAuth auth;
    try {
      auth = FirebaseAuth.instance;
    } catch (_) {
      return IconButton(
        tooltip: "Inbox",
        onPressed: _openInbox,
        icon: const Icon(Icons.inbox_outlined),
      );
    }

    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      initialData: auth.currentUser,
      builder: (context, authSnap) {
        final uid = authSnap.data?.uid ?? "";
        if (uid.isEmpty) {
          return IconButton(
            tooltip: "Inbox",
            onPressed: _openInbox,
            icon: const Icon(Icons.inbox_outlined),
          );
        }

        final stream = FirebaseFirestore.instance
            .collection("chats")
            .where("participants", arrayContains: uid)
            .limit(300)
            .snapshots();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snap) {
            final docs = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final count = _inboxCountFor(docs, uid);
            return _CounterIconButton(
              tooltip: "Inbox",
              icon: Icons.inbox_outlined,
              count: count,
              onPressed: _openInbox,
            );
          },
        );
      },
    );
  }

  int _inboxCountFor(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, String uid) {
    var total = 0;
    for (final d in docs) {
      final data = d.data();
      final rawUnread = data["unread"];
      if (rawUnread is Map) {
        final value = rawUnread[uid];
        final n = value is num ? value.toInt() : 0;
        if (n > 0) {
          total += n;
          continue;
        }
      }

      final lastFrom = (data["lastFrom"] ?? "").toString();
      if (lastFrom.isNotEmpty && lastFrom != uid) {
        total += 1;
      }
    }
    return total;
  }
}

class _NotificationsIcon extends StatelessWidget {
  const _NotificationsIcon({
    required this.routeTracker,
    required this.navigatorKey,
  });

  final RouteTrackerObserver routeTracker;
  final GlobalKey<NavigatorState> navigatorKey;

  void _openNotifications() {
    final route = routeTracker.currentRoute.value;
    if (route == "/notifications") return;
    if (!_canNavigate(navigatorKey)) return;
    try {
      navigatorKey.currentState?.pushNamed("/notifications");
    } catch (_) {
      // Ignore transient navigation failures during route churn.
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = NotificationFeedService.instance;
    return StreamBuilder<List<NotificationItem>>(
      stream: svc.watch(),
      initialData: svc.current,
      builder: (context, snap) {
        final items = snap.data ?? const <NotificationItem>[];
        var unread = 0;
        for (final item in items) {
          if (!item.seen) unread++;
        }

        return _CounterIconButton(
          tooltip: "Notifications",
          icon: Icons.notifications_outlined,
          count: unread,
          onPressed: _openNotifications,
        );
      },
    );
  }
}

class _CounterIconButton extends StatelessWidget {
  const _CounterIconButton({
    required this.tooltip,
    required this.icon,
    required this.count,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
        if (count > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              constraints: const BoxConstraints(minWidth: 18),
              child: Text(
                count > 99 ? "99+" : count.toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}
