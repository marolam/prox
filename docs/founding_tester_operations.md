# Founding tester operations

The growth features extend the existing Big 5: Profile, Nearby/Prox Circle,
Chat, Meetup, and Rating/Party follow-up. Existing in-person referral verification,
five-meetup rewards, paid access, and point balances retain their existing rules.

## Start with the tester cohort

Open **Settings → Founding tester rewards** to apply. An administrator with the
existing Firebase `admin: true` claim opens **Settings → Tester operations** to
select 10–20 people who can actually use Prox with another nearby tester.
Applications do not consume cohort capacity. Approval atomically reserves one
of the configured 10–20 places and starts a 48-hour mission:

1. Complete a profile with a name, photo, seeking keywords, and offering keywords.
2. Exchange real messages with another tester in a direct chat after approval.
3. Complete a meetup after approval, then follow the existing rating flow.

A previously complete profile counts as setup. Chat and meetup evidence must
come after enrollment. Progress is verified by the server; checking off the
separate manual tester checklist cannot complete the mission or earn a reward.
All feedback goes through **Support & feedback**, with a tracked conversation.
Selecting real people and their availability remains an operator task; the app
does not send unsolicited invitations or enroll fabricated testers.

## Enable the referral stage after the first feedback loop

The server configuration is `growthOps/config`. Its initial stage is `testers`.
Use **Tester operations → Configure** to move to `referrals`, then `support`.
The controls also provide a growth kill switch. Pausing growth leaves core Prox
and support submission/replies available.

Initial reward rules are configurable: five welcome points and ten referrer
points, ten single-use invitations per person per UTC day, fifty rewarded
referrals per UTC month, and a separate 100-point monthly referrer payout cap.
Invitation definitions retain the reward amounts in effect when they were made.
New-user welcome rewards apply during the first seven days of an account.

An invitation opens `/referral.html`, which shows a copyable code, an installed-app
link, and platform-specific installation links. A new installation must reopen
the invitation or enter its code; an APK download cannot reliably carry browser
query parameters into an installed app. Deep-link captures retain the first code
across sign-in and offline retries.

Welcome points arrive on accepted eligible attribution. Referrer points require
completed profile setup plus reciprocal chat or a completed-meetup server receipt.
Signup alone cannot unlock them. Stable transaction receipts prevent concurrent
or retried claims from issuing duplicate points. Device-installation and rotating
IP hashes are review signals. Suspicious accounts wait at least 24 hours for
admin review; a shared network is a heuristic, not proof of misconduct. Period
caps remain in force even when an administrator releases a hold.

## Respond visibly and close the loop

Report categories are `bug`, `ux`, `billing`, `feature`, and `question`.
Installed version/build, platform, OS, and device model attach automatically.
Optional JPEG/PNG/WebP screenshots are limited to 5 MB each and loaded through
authenticated Storage reads, without public download links. Drafts retain a
stable submission ID, so uncertain delivery can be retried safely.

The server acknowledges receipt immediately. An operator should add a human
reply the same day and classify severity:

| Severity | Response path |
| --- | --- |
| P0 | Investigate immediately; use the existing hotfix release path |
| P1 | Include in the next patch |
| P2 | Batch for the weekly patch |

Use **Tester operations → Support queue** to view private screenshots, the full
conversation, category, severity, and status. A resolved bug requires its fixed
app version and build. The reporter receives a persisted support reply identifying
that build and can read it under **My reports**. Support can reopen when the
reporter adds details. Automatic receipt does not count as the first human response.
Existing detailed-feedback rewards retain their original two-point daily cap.

## Read the five daily metrics

| Metric | Measurement |
| --- | --- |
| Activation | Auth-created accounts with completed profile and verified peer activity within 24 hours; only matured accounts enter the denominator |
| Referral conversion | Activated referred accounts divided by created single-use invites in the invitation cohort; creation is a proxy for sharing, not proof of delivery |
| Day 1 / Day 7 retention | Auth signup cohorts returning on the target UTC calendar day; shown only after that day ends |
| First response | Median minutes from report creation to the first operator reply; outstanding reports are shown separately |
| Crash-free sessions / errors | Completed opted-in diagnostic sessions without a reported fatal error, plus the three most frequent reported sources |

Basic authenticated session activity supports retention. Sending remote error
reports follows **Share crash reports**. Error sources exclude message text,
profile details, credentials, and coordinates. This pilot session measure cannot
detect every native process death; use Crashlytics for crash investigation and
check the displayed coverage before interpreting a percentage. Bounded backend
queries explicitly expose truncation. The hourly aggregate job and live ops view
use the same cohort definitions.

## Validation and recovery

Run `flutter analyze`, `flutter test`, and
`npm --prefix functions run test:emulators` before releasing. Preserve the native
signing identity and use a new build number for every uploaded package. Test the
Big 5, support screenshots/replies, one successful referral, one held referral,
and the growth kill switch on native clients.

The exact pre-change source, published Android 0.19.0 build 26 binary, local USB
binary, and deployed backend baseline are protected separately. See
[growth_rollback.md](growth_rollback.md) for checksummed artifacts, Firestore/Storage
snapshots, the isolated restore drill, and recovery commands. Redeploying source
does not automatically reverse legitimately issued rewards or subsequent user
activity; choose a targeted recovery from the preserved evidence.
