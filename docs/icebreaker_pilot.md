# Icebreaker pilot

Release candidate `0.22.0+34` implements Icebreaker on the current production
branch. Production backend activation, paired Android/iOS publication, and
physical-device proximity/camera validation are release-time gates.

## Experience

Choose **Nearby > Mode > Icebreaker**, then save. This is deliberate opt-in,
not Normal Passive matching. Both participants keep Nearby open. No automatic
match cards, chat requests, penalties, notifications, or background matching
are created by Icebreaker. Existing Simple Mode restrictions stay unchanged.

A soft ambient screen/circle glow means another participating account appears
nearby. Ambient blue/yellow/amber and increasing brightness indicate approximate
proximity. Compatible search/provide keywords in either direction produce a
shared color, symbol, and four-character mark. This reuses Prox's normalized
complementary keyword policy, not full-profile similarity or hidden inventory.

Several compatible peers can produce several anonymous signals. Each pair's
signal is symmetric and changes between sessions; users choose **Show my
signal** to compare it. Signals carry no peer UID, name, keyword, position, or
direction. Colors can collide, so a visual signal is not identity proof.

**We found each other** shows a short-lived QR and manual code. One participant
scans or enters the other person's code to establish an encounter. Each must
then separately agree to reveal their display names and only the keywords
connecting them. Neither scanning nor unilateral consent reveals keywords.
Afterward, both separately choose Party; the existing server-owned mutual
membership writer creates the connection atomically. Ending the encounter
revokes pending consent without removing an already agreed Party connection.

The empty state offers existing Party value, rather than simulated users.
Icebreaker is an explicit local encounter feature, independent of Normal's
density unlock, saved radius, keyword filters, and Party/Tree/public scope.
It does not unlock public Normal or background discovery.

## Privacy and proximity contract

This is an **approximate GPS pilot**, not a same-room detector. Walls, floors,
indoor accuracy, and movement make seeing/speaking-distance guarantees impossible.
No Bluetooth capability or background location permission is added.

- Maximum measured separation: 30 meters.
- Both fixes must be non-cached, no older than 45 seconds, no more than 5 seconds
  in the future, and accuracy at most 20 meters.
- Measured separation plus both reported accuracies must be at most 45 meters.
- Ambient bands: close <= 10 m, near <= 20 m, around <= 30 m. These are not
  displayed as person locations or exact distances.
- Foreground observation refresh: every 5 seconds, without overlapping requests.
  Each observation requests a high-accuracy foreground fix; stationary Normal's
  low-accuracy location refresh is not treated as sufficient for this pilot.
- Server participation lease: 15 seconds. Signals also expire when the underlying
  location becomes stale, even without another server response.
- Leaving Nearby, choosing another mode, signing out, disabling location, or
  backgrounding clears local signals immediately and attempts server revocation.
  If disconnected, a peer may retain a signal until the existing lease expires.
- QR/code and reveal/Party operations require both current leases, mode settings,
  fresh close locations, active enrolled accounts, and no block in either direction.
- Encounter expiry: 5 minutes. No match or completed-meetup rewards are issued.
- Failed/network/malformed responses clear glow and revealed data and show an
  error. No cached encounter is presented as current.

## Backend rollout

Deploy the `icebreaker` callable and `sweepIcebreaker` scheduler, plus updated
`onPartyWrite` and matching-scope functions that use the shared trusted-edge
policy, together with the updated app. Existing clients must update before the
pilot: unknown modes are not safely interpreted by older apps.

No new Firestore index or rule permission is needed. Server-owned top-level
collections `icebreakerSessions`, `icebreakerCodes`, `icebreakerEncounters`, and
`icebreakerRateLimits` remain unreadable/unwritable to clients under the existing
deny-by-default rules. The callable uses standard account enforcement and quotas,
plus a ten-code-attempts-per-minute throttle. A scheduled sweep deletes expired
documents in batches of up to 500 per collection every 15 minutes.

The pilot query is bounded to 100 latitude-band records and 20 eligible nearby
peers, with at most eight compatible signals. Crowded/saturated queries produce
an explicit error instead of claiming an empty or complete result. This is a
small-gathering pilot, not a claim of city-scale proximity discovery.

## Verification before rollout

Run the rollback safety gate, Flutter analyzer and Icebreaker/matching/session/
circle regressions, backend type-check, and local emulator Icebreaker/Party/scope
tests. Then use two updated physical devices:

1. Enter Icebreaker on only one phone: no signal from the nonparticipating phone.
2. Enter on both, with incompatible keywords: ambient glow only.
3. Use complementary search/provide keywords: compare color, symbol, and mark.
4. Move apart outdoors; verify bands and expiry without interpreting GPS as proof.
5. Test indoors, inaccurate fixes, cached fixes, denied permissions, network loss,
   screen locking, backgrounding, leaving Nearby, and account changes.
6. Scan QR on Android/iOS; test camera denial and manual-code fallback.
7. Confirm a code: no keyword disclosure or Party membership. Consent on one
   phone: still no disclosure. Consent on both: only connecting keywords.
8. Choose Party on one phone: no membership. Both: reciprocal trusted membership.
9. Block/cancel/expire between consent steps: no subsequent disclosure or Party
   write. Existing Normal, Listen, Travel, Treasure and Party searches still work.

Do not deploy, install broadly, or publish until the appropriate device and
rollout confirmation has been given. This implementation does not publish a
new release or change the protected rollback.

## Local validation results

- Safety gate: source snapshot created, no Git conflicts, protected rollback
  release and canonical APK SHA-256 verified.
- Flutter analyzer: no issues.
- Focused Flutter regressions: 58 passed, including Icebreaker service/UI,
  Normal/Treasure peer exclusion, session isolation, circle gestures, Party scope,
  and unchanged Simple Mode behavior.
- Backend TypeScript build: passed.
- Local Firestore emulator regressions: 50 passed, including mutual keyword/
  Party consent, expired leases, blocks, private collection access, in-person
  Party, trusted graph scope, and background matching exclusions.
- Android debug APK: built successfully with native QR scanner integration.
  Signed tester preview subsequently built and installed on R5 and Zy as
  version 0.21.0, build 30, on October 11, 2026. Both installed APK hashes match
  `20fd2a476c9fd60b0f9086d10cc26e1dbf663b0fb3e3a171c3c7684f44476eed`.
  Both apps launched with live processes and no Prox markers in the recent crash
  buffers. Existing app data was retained. Pro Mode preview remains restricted
  to `marty.marola@hotmail.com`. The canonical rollback APK was restored and
  its protected hash verified after installation.
  Backend subsequently deployed as recorded below. Two-device encounter and
  proximity signoff remains outstanding.
- iOS camera text updated; native iOS build/scanner behavior and two-device
  proximity have not been verified on this Windows environment.

## Production backend deployment

The production rollout targets:

- New: `icebreaker`, `sweepIcebreaker`.
- Updated Party/trust: `onPartyWrite`, `getMatchingAccess`,
  `onMatchingForegroundPresence`, `onMatchingPartyChanged`,
  `onMatchingBlockChanged`.
- Updated coupled background paths: `onBackgroundPresence`,
  `onBackgroundMatchAlert`, `getBackgroundOpportunity`,
  `listBackgroundOpportunities`.

Verify all targeted functions are `ACTIVE`, confirm the cleanup scheduler is
enabled, and exercise the signed-out endpoint before publishing the client. No
Firestore rules or indexes are changed. Authenticated two-device proximity,
camera scanning, and bilateral keyword/Party consent still require the checklist
above; endpoint verification alone is not device signoff.
