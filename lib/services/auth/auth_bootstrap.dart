import "dart:async";
import "package:prox/services/matching/background_matching_service.dart";

import "package:firebase_auth/firebase_auth.dart";
import "package:prox/services/matching/matching_runtime_service.dart";
import "package:prox/services/matching/matching_mode_service.dart";
import "package:prox/services/matching/treasure_compass_service.dart";
import "package:prox/services/notification_feed_service.dart";
import "package:prox/services/points_service.dart";
import "package:prox/services/presence_writer.dart";
import "package:prox/services/push_notifications.dart";
import "package:prox/services/runtime_diagnostics_service.dart";
import "package:prox/services/secure_credential_store.dart";
import "package:prox/services/user_profile_service.dart";
import "package:prox/services/geoquery_service.dart";
import "package:prox/services/user_settings_service.dart";
import "package:prox/services/billing_entitlement_sync_service.dart";
import "package:prox/services/growth_service.dart";
import "package:prox/services/matching_access_service.dart";

class AuthBootstrap {
  AuthBootstrap._();

  static final AuthBootstrap instance = AuthBootstrap._();

  StreamSubscription<User?>? _subscription;
  Future<void>? _starting;
  String? _uid;

  Future<void> start() {
    if (_subscription != null) return Future<void>.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    await UserSettingsService.instance.ensureLoaded();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    unawaited(GrowthService.instance.bindAccount(_uid));
    final initialSync = BillingEntitlementSyncService.instance.bindAccount(
      _uid,
    );
    MatchingModeService.instance.syncSessionToServer();
    _subscription = FirebaseAuth.instance.authStateChanges().listen(
      (user) {
        final next = user?.uid;
        if (next == _uid) return;
        if (_uid != null)
          SecureCredentialStore.instance.invalidatePendingOperations();
        _uid = next;
        unawaited(GrowthService.instance.bindAccount(next));
        unawaited(BillingEntitlementSyncService.instance.bindAccount(next));
        MatchingModeService.instance.syncSessionToServer();
        PresenceWriter.instance.stopForSignOut();
        MatchingRuntimeService.instance.clearSession();
        TreasureCompassService.instance.clearSession();
        PointsService.instance.clearSession();
        UserProfileService.instance.clearSession();
        GeoQueryService.instance.clearSession();
        NotificationFeedService.instance.clear();
        unawaited(PushNotifications.instance.dispose());
      },
      onError: (Object error, StackTrace stack) {
        RuntimeDiagnosticsService.instance.record(
          error,
          stack,
          operation: "Account session",
        );
      },
    );
    await initialSync;
    MatchingAccessService.instance.start();
    await BackgroundMatchingService.instance.start();
  }

  Future<void> prepareForManualSignOut() async {
    unawaited(GrowthService.instance.bindAccount(null));
    await BackgroundMatchingService.instance.stopForSignOut();
    final reset = BillingEntitlementSyncService.instance.bindAccount(null);
    SecureCredentialStore.instance.invalidatePendingOperations();
    PresenceWriter.instance.stopForSignOut();
    MatchingRuntimeService.instance.clearSession();
    TreasureCompassService.instance.clearSession();
    PointsService.instance.clearSession();
    UserProfileService.instance.clearSession();
    GeoQueryService.instance.clearSession();
    NotificationFeedService.instance.clear();
    await reset;
  }
}
