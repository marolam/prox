# Meetup feedback and mutual Party requests

Build candidate: `0.19.0+21`. Uploaded iOS build 20 does not contain these changes.

Thumbs-up reveals **Add to Party** and **Not Right Now**. Each choice has a
confirmation explaining membership and Party-visible profile sharing. Thumbs-down
opens a confirmation with an optional, private comment (up to 1,000 characters).
Nothing is selected or submitted by default. Save failures are displayed and may
be retried; secondary accounting does not turn a saved rating into a failed UI.

The callable `respondToPartyConnection` validates the signed-in participant and
completed meetup (or both arrival acknowledgements). It writes the rating, trust
receipt, activity receipt and Party choice in one transaction. A per-person,
per-meetup receipt makes network retries idempotent. Previously submitted feedback
cannot silently change on a retry; later Party choices happen in the pending area.

`partyConnections/{sha256(sorted participant IDs)}` holds two independent choices.
The second affirmative choice atomically creates both canonical
`users/{uid}/party/{otherUid}` entries with `mutual: true`. The Party list listens
to those entries and the existing Party-profile page displays every enabled field.
Existing mutual members remain connected when they rate another meetup.

Either person's **Not Right Now** leaves the connection pending, without creating
membership or granting Party profile access. **Pending Party Add** appears in the
Party screen and provides acceptance, deferral, reminders and blocking. Reminders
create durable notification events delivered by FCM; tapping one opens `/party`.
There is a 24-hour per-sender notification cooldown, including repeated changes of
consent. Disabled reminder buttons explain the cooldown.

Pending connections expire after **7 days without activity**. Decisions and allowed
reminders update the activity deadline. The server rejects expired actions even
before the hourly sweeper marks the record expired; the UI also hides expired
requests. Removing or blocking clears both membership projections and consent.
Blocking from another app screen is handled by `onPartyConnectionBlock`. Current
state is reread transactionally so delayed trigger deliveries cannot reconnect
removed, blocked or deleted accounts. Unblocking does not restore a connection.
Removal, blocking, acceptance, deferral and reminders have confirmation dialogs.

Rules reserve connection writes for the server, restrict reads to participants,
require both confirmed memberships and no block for Party-profile access, and
keep written rating comments readable only by their author or an administrator.
Historical one-sided Party entries are no longer treated as accepted members;
this change does not infer new consent from them. New pending connections are
created by the new completed-meetup feedback flow.

## Rollout

Deploy the backend and Firestore rules before distributing build 21. Required
new functions: `respondToPartyConnection`, `onPartyConnectionNotification`,
`onPartyConnectionBlock`, `sweepPartyConnections`. Also deploy the updated
`onPartyWrite`, `deleteMyAccount` and `onAuthDelete`. Existing trust and meetup
accounting functions must be present. New queries use automatic single-field
indexes (`members` array membership and `expiresAt` range); no composite index
is required. This implementation has not deployed any live backend or app build.

Validate with:

```powershell
flutter --no-version-check analyze --no-pub
flutter --no-version-check test --no-pub
npm --prefix functions run test:emulators
```

Device acceptance: two signed-in users finish a meetup, rate it, then select Add
on both devices. Both lists should update without refresh, and all enabled Party
profile fields should display. Repeat with one deferral, later acceptance,
reminder delivery, blocking, and removal. FCM/APNs delivery and the live callable
must be checked after backend deployment; emulator tests do not send real pushes.
