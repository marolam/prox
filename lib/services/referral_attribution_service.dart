export "package:prox/services/referral_attribution.dart" show ReferralAttribution;

import "package:prox/services/referral_attribution.dart";

class ReferralAttributionService {
  ReferralAttributionService._();

  static final ReferralAttribution instance = ReferralAttribution.instance;
}