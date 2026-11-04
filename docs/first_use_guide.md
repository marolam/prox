# Welcome and first steps

Newly created accounts see a purpose-first welcome before profile and permission
setup. Choose **Show me how** for the guided tour, or **Explore on my own**.
Existing accounts are not automatically interrupted. Account creation within the
last day identifies a new account on its first local launch; an acknowledged
welcome stays acknowledged.

The six-stop tour highlights real navigation controls for Profile, Nearby,
Meetups, Party, Referrals, and Settings, including where to find HQ and Support.
It explains keywords, the Prox Circle, discovery modes, requests, chat, public
meetups, consent, and in-person invitations. **Back**, **Next**, and **Finish
later** let people learn at their own pace. The optional example walkthrough can
be exited without completion; mandatory walkthrough callers retain their
existing completion requirement.

The first-steps checklist records:

- Profile and keywords only after a successful profile save.
- Exploring Nearby.
- Learning requests, chat, and meetups.
- Learning the invitation process, not sending an invitation.

No recruitment quota, invitation, match, or reward is required to complete the
learning checklist. A locally growing community can provide more opportunities,
but no connection or reward is promised.

First-visit tips expand on tap and can be dismissed. Hide the checklist at any time. Replay via
**Settings > Replay welcome tour**, **Settings > User's Guide**, or the
**What do I do? > Welcome tour and first steps** action in Simple Mode. Replay
restores the checklist and tips without clearing completed tasks. Restarting the
app preserves the current step, but waits for an explicit resume rather than
interrupting navigation. Progress is versioned, per-account, and local to the
device; reinstalling or clearing app data resets it.

## Invitation and access boundaries

Opening the tour or an invitation explanation never creates a QR, sends a
request, changes discovery mode, grants access, or adds a Party member.
**Show my invitation QR** opens Referrals; the inviter must explicitly create
the single-use, expiring QR there. In Simple Mode, restricted tabs remain
restricted, including guide/empty-state shortcuts.

Stay together while the recipient installs, then reopen or refresh the QR to
complete in-person verification. Both parties must meet existing location,
eligibility, expiry, and consent checks. Downloading, forwarding a screenshot,
or entering an ordinary referral code does not replace verification for full
new-account access. Party inclusion remains an explicit separate choice.

Authentication, profile requirements, presence rehearsal, permissions, policy
prompts, active-meetup routing, trust restrictions, and Pro preview eligibility
retain their existing priority. The tutorial does not navigate away from
another route or bypass an access check.

## Storage and accessibility

Writes are serialized and acknowledged only after persistence succeeds.
Failures are recorded through runtime diagnostics and reported in the UI;
welcome loading offers retry or an explicit choice to continue without saving
guide progress. No profile text, location, or invitation tokens are stored in
guide progress.

Welcome, tour, checklist, QR instructions, and profile introduction scroll on
small screens and at large text sizes. Learning cards have a bounded share of
the home screen and are hidden while the keyboard is open. The live tour blocks
underlying interactions; example walkthroughs do not contact real users.

## Candidate validation: 0.22.0+32

- Flutter analyzer: no issues.
- Flutter suite: 450 passed, 3 skipped.
- Layout tests include a 320 x 568 screen, double-size text, system navigation
  padding, and keyboard insets. Learning panels preserve at least 70 percent of
  the available routed-content height.
- Signed Android candidate installed in place on Samsung SM-S901U and Moto
  g play 2024 without clearing app data.
- Both devices passed Settings replay, pause/restart/resume, the six tour stops,
  optional example exit, completion, and persisted checklist checks. Moto also
  passed live Back navigation. No real invitations or meetup requests were sent.
- The production signing certificate and protected rollback release were
  verified. Temporary signing copies were removed after the build.

## Verified publication: November 4, 2026

The user authorized publication after candidate validation. Production tag
`v0.22.0+32` binds commit `2ff282efd41e40b7250178a53032aaf247255f3c`.
The [paired release workflow](https://github.com/marolam/prox/actions/runs/41813367110)
passed backend safety checks, application analysis/tests, signed Android/iOS
builds, native package/version checks, TestFlight upload, public asset publication,
anonymous pinned/latest APK verification, and Android update-policy activation.

- [Published release](https://github.com/marolam/prox/releases/tag/v0.22.0%2B32):
  Android APK, iOS IPA, and release manifest; stable GitHub latest.
- Android package: `com.prox.app`, version `0.22.0`, build `32`.
  Published APK SHA-256:
  `d8d566bc31f4da963826f5492768a5912d7bd83f077d4c6eb460c9d40d737488`
  (87,485,570 bytes). The anonymous latest download, manifest, and production
  signing certificate were independently verified.
- iOS bundle: `com.prox-us.prox`, version `0.22.0`, build `32`.
  Published IPA SHA-256:
  `73d136512beed81cc2b20c5f2a42066cc80a0d4b2b7ac2f5de47da607d08f904`
  (42,430,811 bytes). App Store Connect upload reported success.
- Remote Config version `22` enforces latest/minimum `0.22.0+32` through the
  highest-priority Android-only condition, including legacy clients, with the
  verified version-pinned APK URL. Separate iOS defaults were not advanced.
- The live referral endpoint is `ACTIVE`; ordinary, fallback, and growth Android
  targets already use production latest, so no backend redeployment was needed.
  The permanent Tester Portal download now serves this release too.
- Both connected Android phones received the actual published APK in place of
  the local candidate, without clearing app data. Version/build and running
  processes were verified. Moto retained its completed learning progress and
  launched past the update check. Samsung was locked during the final UI check;
  its complete tutorial checks had passed on the candidate. Neither published
  process reported a fatal application exception.
- Protected private `v1.0` and the original local canonical rollback APK passed
  verification again after publication.

Apple processing and build-32 tester availability remain pending: read-only
checks at 10:55 and 10:56 UTC still listed build 31 as the most recent visible
build. The external TestFlight public link remains disabled. This publication
does not claim public App Store availability, a public iPhone QR installation
path, or a completed external beta review.
