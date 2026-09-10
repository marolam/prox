import "package:flutter_test/flutter_test.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/services/matching/prox_circle_interaction_policy.dart";

void main() {
  test("restored Active mode remains eligible to cycle", () {
    final discovery = const MatchDiscoverySettings.defaults().copyWith(
      modeKind: MatchingModeKind.normal,
      normalMode: NormalMatchMode.active,
    );

    expect(
      ProxCircleInteractionPolicy.canCycle(
        discovery: discovery,
        sessionUnlocked: false,
      ),
      isTrue,
    );
    expect(
      ProxCircleInteractionPolicy.nextMode(discovery.modeKind),
      MatchingModeKind.listen,
    );
  });

  test("cycle order returns Off to Normal", () {
    expect(
      ProxCircleInteractionPolicy.nextMode(MatchingModeKind.off),
      MatchingModeKind.normal,
    );
  });

  test("post-hold suppression expires instead of consuming a future tap", () {
    final now = DateTime(2026, 8, 30, 12);
    expect(
      ProxCircleInteractionPolicy.shouldSuppressTap(
        now: now,
        suppressUntil: now.add(const Duration(milliseconds: 200)),
      ),
      isTrue,
    );
    expect(
      ProxCircleInteractionPolicy.shouldSuppressTap(
        now: now.add(const Duration(milliseconds: 500)),
        suppressUntil: now.add(const Duration(milliseconds: 450)),
      ),
      isFalse,
    );
  });
}
