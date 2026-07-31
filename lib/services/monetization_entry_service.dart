import "package:flutter/material.dart";

import "package:prox/screens/monetization/business_paywall_screen.dart";

class MonetizationEntryService {
  MonetizationEntryService._();
  static final MonetizationEntryService instance = MonetizationEntryService._();

  Future<void> openBusinessPaywall(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const BusinessPaywallScreen(),
      ),
    );
  }
}
