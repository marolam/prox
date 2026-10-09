import "package:flutter_test/flutter_test.dart";
import "package:prox/services/device_storage_service.dart";
import "package:prox/services/referral_attribution.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await DeviceStorageService.instance.set(
      "pending_referral_signal_v1",
      <String, dynamic>{},
    );
  });

  Future<Map<String, dynamic>?> _capture(String rawUrl) async {
    await ReferralAttribution.instance.captureFromLaunchUri(Uri.parse(rawUrl));
    await DeviceStorageService.instance.load();
    return DeviceStorageService.instance.getMap("pending_referral_signal_v1");
  }

  test("captures code from code/ref pair", () async {
    final payload = await _capture(
      "https://prox-us.com/?code=INV123&ref=user_abc",
    );

    expect(payload, isNotNull);
    expect(payload!["code"], "INV123");
    expect(payload["ref"], "user_abc");
  });

  test(
    "captures code-only landing links with server-resolved ownership",
    () async {
      for (final url in [
        "https://www.prox-us.com/referral.html?code=INV123",
        "prox://referral?code=INV123",
      ]) {
        final payload = await _capture(url);
        expect(payload!["code"], "INV123");
        expect(payload["ref"], isNull);
      }
    },
  );

  test("captures code aliases but never treats ref as code", () async {
    final fromReferralAlias = await _capture(
      "https://prox-us.com/?referral=ALIAS42&ref=user_abc",
    );
    expect(fromReferralAlias, isNotNull);
    expect(fromReferralAlias!["code"], "ALIAS42");
    expect(fromReferralAlias["ref"], "user_abc");

    final fromInviteAlias = await _capture(
      "https://prox-us.com/?invite=INVITE9&ref=user_abc",
    );
    expect(fromInviteAlias, isNotNull);
    expect(fromInviteAlias!["code"], "INVITE9");
    expect(fromInviteAlias["ref"], "user_abc");
  });

  test(
    "ignores ref-only links so uid is not mis-read as referral code",
    () async {
      final payload = await _capture("https://prox-us.com/?ref=user_abc");

      expect(payload, isEmpty);
    },
  );

  test("accepts token links without code when ref is present", () async {
    final payload = await _capture(
      "https://prox-us.com/?t=T-ABCDEF123456789012&ref=user_abc&party=1",
    );

    expect(payload, isNotNull);
    expect(payload!["token"], "T-ABCDEF123456789012");
    expect(payload["ref"], "user_abc");
    expect(payload["code"], isNull);
    expect(payload["party"], isTrue);
    expect(payload["inperson"], isTrue);
  });

  test("accepts token-only links without ref", () async {
    final payload = await _capture(
      "https://prox-us.com/?t=T-ABCDEF123456789012",
    );

    expect(payload, isNotNull);
    expect(payload!["token"], "T-ABCDEF123456789012");
    expect(payload["ref"], isNull);
    expect(payload["code"], isNull);
    expect(payload["party"], isFalse);
    expect(payload["inperson"], isFalse);
  });

  test("accepts wrapped token-only links from prox.page.link", () async {
    final payload = await _capture(
      "https://prox.page.link/?link=https%3A%2F%2Fprox-us.com%2F%3Ft%3DT-ABCDEF123456789012%26party%3D1",
    );

    expect(payload, isNotNull);
    expect(payload!["token"], "T-ABCDEF123456789012");
    expect(payload["ref"], isNull);
    expect(payload["code"], isNull);
    expect(payload["party"], isTrue);
    expect(payload["inperson"], isTrue);
  });
}
