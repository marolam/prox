import 'package:flutter/material.dart';
import 'package:prox/screens/store/prox_points_store_screen.dart';

/// Compatibility entry for the former duplicate wallet implementation.
/// All ownership and purchase behavior now uses the canonical store.
class ProxPointsScreen extends StatelessWidget {
  const ProxPointsScreen({
    super.key,
    this.debugUidOverride,
    this.walletUnlockedOverride,
    this.openBillingActivationOverride,
    this.unlockedBodyOverride,
  });
  final String? debugUidOverride;
  final Future<bool> Function(String uid)? walletUnlockedOverride;
  final Future<void> Function(BuildContext context)?
  openBillingActivationOverride;
  final WidgetBuilder? unlockedBodyOverride;

  @override
  Widget build(BuildContext context) => ProxPointsStoreScreen(
    debugUidOverride: debugUidOverride,
    storeUnlockedOverride: walletUnlockedOverride,
    openBillingActivationOverride: openBillingActivationOverride,
    unlockedBodyOverride: unlockedBodyOverride,
  );
}
