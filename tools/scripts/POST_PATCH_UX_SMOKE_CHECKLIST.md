# Post-Patch UX Smoke Checklist

Date: 2026-03-10
Scope: Meetup re-entry, top action buttons, Treasure Hunt, Travel mode clarity, tester unlock parity, referral attribution, in-person Party handshake + referral Party policy.

## Setup

1. Use two devices with fresh app launch.
2. Sign in with two tester users that can chat each other.
3. Keep one device on Nearby and the other in chat when needed.

## Test 1: Top Action Buttons

1. Open `/home`, `/nearby`, `/matches`.
2. Verify top-right floating action cluster is visible only on these pages.
3. Tap `Inbox` icon.
4. Expected: navigates to `/inbox`.
5. Tap `Notifications` icon.
6. Expected: navigates to `/notifications`.
7. Open `/dashboard`, `/meetup_plan`, `/meetup_live`, `/settings`.
8. Expected: floating top action cluster is not shown and does not overlap controls.

Pass criteria:
- No overlap on non-matching screens.
- Both icons navigate when visible.

## Test 2: Meetup Re-Entry Is Discoverable

1. In chat, request and accept a meetup.
2. Open planner, set pin, then back out to chat.
3. Navigate to Meetups tab.
4. Expected: meetup card appears with status/location chips.
5. Tap `Open planner` or `Open live` (depending on status).
6. Expected: correct meetup screen opens.
7. Tap `Open chat`.
8. Expected: returns to the same chat thread.

Pass criteria:
- Meetup can be reopened from Meetups tab after leaving chat.

## Test 3: Planner Map/Pin Wording Clarity

1. Open planner.
2. Confirm status text includes guidance: pick pin then confirm together.
3. Confirm primary action label is `Set pin to my location`.
4. Confirm secondary action label is `Move pin manually (coords)`.

Pass criteria:
- Labels/guidance match exactly.

## Test 4: Treasure Hunt Compass Entry

1. Set mode to `Normal`.
2. Open Treasure Hunt screen.
3. Expected: shows prompt and `Switch to Treasure Hunt` button.
4. Tap `Switch to Treasure Hunt`.
5. Expected: mode flips without leaving flow.
6. If no targets, verify message mentions radius/keywords.
7. If targets exist, verify compass card renders with bearing text.

Pass criteria:
- User can always enter Treasure Hunt mode from screen.
- Empty state is explicit and actionable.

## Test 5: Travel Mode Clarity

1. Open mode chooser, select `Travel`.
2. Verify subtitle reads: `Recent movers only (last ~30 min)`.
3. If Nearby empty, verify detail text says to switch to Normal for broader results.

Pass criteria:
- Travel behavior is clearly explained in both selector and empty state.

## Test 6: Tester Unlock Parity (No Bypass)

1. Sign in with a low-progress tester account.
2. Open Referrals.
3. Expected before unlock criteria are met: progression lock is shown.
4. Complete the same unlock criteria required for normal users.
5. Re-open Referrals and support/tester-gated surfaces tied to progression.
6. Expected after unlock criteria are met: features are accessible.

Pass criteria:
- Testers follow normal progression unlock rules.
- Access appears only after unlock criteria are satisfied.

## Test 7: Referral Attribution (QR)

1. Generate QR/link from referrer account.
2. Join with a brand-new invitee account via QR/link path.
3. Verify invitee user doc has `referrer` and `referralCodeUsed` set.
4. Repeat join flow using an invitee account that already has `referrer` set.
5. Expected: existing referrer remains unchanged.

Pass criteria:
- First attribution sticks.
- Existing attribution is not overwritten.

## Test 8: In-Person Direct Party Handshake

1. Use two nearby devices/users with `Party Mode` ON.
2. On device A open Party and tap `Direct invite to Party`.
3. On device B do the same so both show a live code.
4. Enter B's code on A and submit.
5. Expected on A: `Step 1 done` message and diagnostics card shows `awaiting peer confirm`.
6. Enter A's code on B and submit.
7. Expected on B: paired success message.
8. Return to Party list on both devices.
9. Expected: both users appear in each other's Party list.

Pass criteria:
- Pair completes only after both users confirm.
- Single-sided submit does not immediately force bilateral pairing.

## Test 9: Referral Toggle Matrix (In-Person QR)

1. Referrer opens Referrals and turns OFF `Allow in-person QR referrals into my Party`.
2. Generate/share QR and let a brand-new invitee join via QR.
3. Expected: referral attribution works, but no automatic Party add for either side.
4. Referrer turns toggle ON.
5. Regenerate/refresh code if needed, then repeat with another brand-new invitee via in-person QR.
6. Expected: referral attribution works and Party auto-join path executes (invitee side immediate; referrer side after auth sync).

Pass criteria:
- Toggle OFF blocks referral-driven Party auto-join.
- Toggle ON allows referral-driven Party auto-join for in-person QR path.

## Test 10: No Auto Party on Online/Store Join

1. Have a brand-new user install/open app normally (no in-person QR flags).
2. Complete sign-in and onboarding.
3. Open Party screen.
4. Expected: no referrer auto-added to Party.
5. Verify referral may still be attributed if standard invite code path is used.

Pass criteria:
- Standard online/store onboarding never auto-adds Party members out of the gate.

## Test 11: Tutorial Replay Spinner Recovery

1. Open Settings and tap `Replay quick tutorial`.
2. Expected: profile edit screen opens.
3. If loading takes too long, expected fallback UI appears with `Retry` and `Continue` buttons by 12s.
4. Tap `Retry` once.
5. Expected: loading attempts again.
6. Tap `Continue` if still slow.
7. Expected: profile form opens and tutorial bubble remains active.

Pass criteria:
- Replay never stays on an indefinite spinner.
- User can always proceed via `Continue`.

## Log Spot Check (Optional)

Run after each test block:

```powershell
adb -s <DEVICE_ID> logcat -d | Select-String -Pattern "FATAL EXCEPTION|permission-denied|NoSuchMethodError|Unhandled Exception|Matchmaker|Meetup"
```

Expected:
- No fatal crash lines.
- No new permission-denied regressions in tested flow.

## Report Format

Release blockers for current cycle:

- `T2`, `T7`, `T8`, `T10`, `T11` must be `PASS` for GO.

Return a single line per test:

- `T1 PASS` or `T1 FAIL: <short reason>`
- `T2 PASS` or `T2 FAIL: <short reason>`
- `T3 PASS` or `T3 FAIL: <short reason>`
- `T4 PASS` or `T4 FAIL: <short reason>`
- `T5 PASS` or `T5 FAIL: <short reason>`
- `T6 PASS` or `T6 FAIL: <short reason>`
- `T7 PASS` or `T7 FAIL: <short reason>`
- `T8 PASS` or `T8 FAIL: <short reason>`
- `T9 PASS` or `T9 FAIL: <short reason>`
- `T10 PASS` or `T10 FAIL: <short reason>`
- `T11 PASS` or `T11 FAIL: <short reason>`
