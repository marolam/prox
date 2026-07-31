import "package:flutter/widgets.dart";
import "package:provider/provider.dart";

import "services/profile_service.dart";
import "services/chat_service.dart";
import "services/meetup_service.dart";
import "services/push_notifications.dart";
import "services/user_settings_service.dart";
import "services/net/prox_connectivity_service.dart";
import "services/offline/offline_outbox_service.dart";
import "services/business_mode_service.dart";
import "services/color_match_service.dart";
import "services/prox_store_service.dart";
import "services/dashboard_service.dart";
import "services/support_service.dart";
import "services/referral/referral_service.dart";
import "services/points_service.dart";

class AppProviders extends StatelessWidget {
  final Widget child;
  const AppProviders({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    UserSettingsService.instance.ensureLoaded();

    // Start connectivity + outbox flush (idempotent).
    // ignore: discarded_futures
    ProxConnectivityService.instance.start();
    // ignore: discarded_futures
    OfflineOutboxService.instance.start();

    return MultiProvider(
      providers: [
        Provider<ProfileService>.value(value: ProfileService.instance),
        Provider<ChatService>.value(value: ChatService.instance),
        Provider<MeetupService>.value(value: MeetupService.instance),
        Provider<PushNotifications>.value(value: PushNotifications.instance),
        Provider<BusinessModeService>.value(value: BusinessModeService.instance),
        Provider<ColorMatchService>.value(value: ColorMatchService.instance),
        Provider<ProxStoreService>.value(value: ProxStoreService.instance),
        Provider<DashboardService>.value(value: DashboardService.instance),
        Provider<SupportService>.value(value: SupportService.instance),
        Provider<ReferralService>.value(value: ReferralService.instance),
        Provider<PointsService>.value(value: PointsService.instance),
      ],
      child: child,
    );
  }
}