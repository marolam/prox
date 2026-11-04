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

This is a local Android candidate, not a public release. iOS build/distribution
and public download-target updates remain part of a separately confirmed
publication.
