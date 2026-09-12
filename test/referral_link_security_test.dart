import "package:flutter_test/flutter_test.dart";
import "package:prox/services/referral_attribution.dart";

void main() {
  test("referral links use an exact HTTPS host allowlist", () {
    for (final url in [
      "https://prox-us.com/r?ref=friend&code=123",
      "https://www.prox-us.com/r?ref=friend&code=123",
      "https://prox.page.link/?link=legacy",
      "prox://referral?ref=friend&code=123",
    ]) {
      expect(ReferralAttribution.isTrustedReferralUri(Uri.parse(url)), isTrue, reason: url);
    }
    for (final url in [
      "https://evilprox-us.com/r?ref=attacker",
      "https://prox-us.com.evil.test/r",
      "https://prox.page.link.evil.test/r",
      "http://prox-us.com/r",
      "https://user:password@prox-us.com/r",
      "https://prox-us.com:444/r",
      "javascript://prox-us.com/r",
      "prox://attacker/referral",
    ]) {
      expect(ReferralAttribution.isTrustedReferralUri(Uri.parse(url)), isFalse, reason: url);
    }
  });
}
