# Continuous background matching

Implemented locally on September 13, 2026. Production Functions, rules, indexes and mobile releases must be rolled out together before this feature is available to testers.

## User behavior

- New sessions still start in Normal Passive. Opening a notification or an opportunity does not activate matching. The connection screen requires the same three-second Prox-circle hold before Normal Active and opening chat.
- Sound & alerts contains an explicit background-location disclosure and opt-in. Collection requires Always / Allow all the time permission. Turning background matching, location, or matching off stops the native collector and invalidates its server presence; manual sign-out stops it before credentials are cleared.
- Significant means at least two distinct normalized keywords in each complementary direction: my Searching For against their Can Provide, and their Searching For against my Can Provide. Repeated entries, case differences and generic placeholder words cannot inflate strength. A percentage score alone does not qualify.
- Default allowance: three significant alert attempts per rolling 24 hours. The setting offers one, three, or six. All choices retain at least four hours between alerts and at most one alert about the same person per seven days. Quiet hours default to 10 PM–8 AM in the device's current local time. These are upper limits, not a notification quota; quiet hours and availability can reduce the total. No paid unlock is implemented. Future entitlements can control access to higher limits without reducing keyword strength or repeat protection.
- Ordinary opportunities remain silent and are accessible from the Background matches button in Nearby. This view fetches a bounded snapshot when opened or refreshed, and the connection is checked again before opening chat.
- Normal background opportunities include Passive/Passive users who opted in. Listen connects other Listen users without keyword or business/age/party filters. Travel only connects other Travel users with fresh movement observations and a conservative distance allowance for accuracy and elapsed movement. Treasure Hunt retains its separate compass snapshot and does not generate ordinary proximity matches or significant alerts.
- Significant notifications are reserved for Normal mode and suppressed when either device reports at least 7 m/s. No automatic chat message or meeting request is sent.

## Battery, network and location behavior

Android uses a native location foreground service with a silent ongoing notification and balanced-power location requests. Normal/Listen uploads are no more frequent than five minutes, after movement of roughly 250 meters, with a stationary refresh target of 15 minutes. Travel uses a one-minute minimum upload interval. Android batches normal updates and makes an occasional balanced-power location request for stationary freshness. Boot/package-update restoration is best effort under Android restrictions.

iOS uses native Core Location at approximately hundred-meter accuracy, significant-change monitoring for eligible system relaunches, and standard background updates to retain stationary freshness. Upload throttling is the same as Android. Core Location callback delivery and energy use require real-device measurement; upload limits are not a guarantee of a specific battery percentage. Standard background updates can cost more energy than significant-change monitoring alone.

Coordinates are rounded to three decimal places, with extra uncertainty included in distance checks. Only the current private location document is stored, with no route-history collection. At most one native Firestore location write is outstanding per collector generation. Offline samples cannot be treated as fresh when eventually delivered. Locations expire for matching after 30 minutes; Travel additionally requires a fix no older than 90 seconds and movement of 0.6–100 m/s.

The phone does not run live background profile queries. Each accepted location update triggers a server geographic query bounded to 80 location rows, 24 profile candidates, and eight pair evaluations, stopping after three eligible pairs. Scan starts are throttled to five minutes in Normal/Listen and one minute in Travel. Background distance is bounded to the smaller participant radius, capped at ten miles; it never widens a user's smaller selected radius. Dense areas can exceed the candidate cap, so this is best-effort discovery rather than an exhaustive search.

The operating system may suspend updates after force-stop, revoked permission, power restrictions, unavailable location or connectivity. “Device is on” cannot by itself guarantee continuous execution. Relevant platform guidance: [Android background location](https://developer.android.com/develop/sensors-and-location/location/background), [Android battery guidance](https://developer.android.com/develop/sensors-and-location/location/battery), and [Apple background location](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background).

## Server enforcement and cleanup

- A transaction rechecks both users' consent, selected device, profile availability, blocks, deletion markers, meetup state, mode, freshness, mutual radius and applicable matching criteria. The same checks run again before delivery and when opening an opportunity.
- Private location cannot be read by peers or through client collection-group queries. Rules bind writes to the selected device, require server receipt time, bound metadata and prohibit a history field.
- Clients cannot read, forge or reset opportunity receipts, notification budgets, pair cooldowns, outbox records or scan gates. Authenticated callables disclose only revalidated connection details, never coordinates.
- Notification budgets and pair cooldowns are reserved atomically. The outbox claims an attempt durably before calling FCM. A crash or ambiguous delivery result is not retried, favoring missed alerts over repeated interruptions. Failed or suppressed attempts can consume the allowance. Generic lock-screen copy includes no peer identity or keywords.
- TTL fields cover private presence, opportunities, outbox entries and pair cooldowns. Matching checks expiry immediately; physical TTL deletion is asynchronous. Account deletion removes the user's subtree and references to that user from other users' background collections.

## Validation and release

Local validation: Flutter analysis, Android debug APK build, 241 passing Flutter tests with three existing skips, and 84 passing backend/rules emulator tests. Emulator notification tests inject fake delivery functions and never send real FCM notifications. An iOS build cannot be verified from this Windows workspace.

Release sequence: deploy the new Firestore rules and indexes/TTL policies; wait for geographic and deletion indexes to finish building; deploy `onBackgroundPresence`, `onBackgroundMatchAlert`, `getBackgroundOpportunity`, `listBackgroundOpportunities` and the updated account-deletion function; then distribute updated Android and iOS builds. The existing public-profile projection must also be deployed and operational. Background matching stays off until explicit device consent.

Before general release, test two real devices while stationary, walking, traveling, locked, offline, after restart, after sign-out and after permission revocation. Verify real FCM delivery, silent/sound channels, timezone changes, a repeated pair, changed criteria, and the alert-to-hold-to-chat path. Measure battery and network use over several hours, especially stationary iOS behavior. Complete the relevant store background-location disclosures with the release.
