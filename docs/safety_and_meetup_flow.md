# Safety access and definitive meetup outcomes

Released: `0.19.0+23` on September 12, 2026, including the meetup feedback/Party changes merged in PR #10. Required functions and exact tagged rules are deployed. Android is published with its update policy active; Apple validated build 23 for the internal TestFlight group. External group assignment and beta submission/review remain pending. See `automatic_paired_releases.md` for verified distribution status.

## User experience

- A reserved Safety strip is present above the navigator, including startup/sign-in, maps, dialogs, keyboards, and update enforcement. It preserves the underlying screen and dialog when opened. Safety opens a confirmation panel; the next tap opens the phone app for US 911 or confirms the selected chat/meetup exit.
- Emergency dialing does not require authentication, Firebase, location permission, or a successful cancellation. The app labels 911 as US-specific, explains the phone confirmation, and provides a manual dialing fallback. It does not claim to dispatch help or share location. Reference: https://www.911.gov/calling-911/
- Meetup-only cancellation leaves chat available. Ending a direct chat also cancels its active meetup and disables further messages. Group exits remove only the caller; if they manage the group, the first remaining member takes over. All effects are explained on the confirmation panel before its action buttons.
- No private safety reason or emergency action is sent to the peer. A peer can see that the meetup/chat ended. Cancellation is neutral and does not reduce a rating.
- The planner/live screens explain agreement, pin confirmation, travel, and arrival. The agreed pin is locked after confirmation. Arrival code controls are labeled and visible in the main content; the displayed code refreshes. Opening external Maps does not complete the meetup.
- Back navigation asks whether to continue, open Safety, or leave pending. Leaving pending is allowed and explained; it does not silently cancel or mark success. Chat remains available during coordination without resetting progress.

## Lifecycle and storage

- `endMySafetySession` authenticates the participant and atomically cancels requested/accepted/live meetups, optionally closing chat. It preserves already-terminal meetup outcomes and tolerates duplicate direct-chat cancellation.
- Rules protect chat closure, reject later messages, prevent backward meetup transitions and confirmed-pin changes, and prevent active-meetup deletion. Completed/cancelled/expired outcomes cannot be resurrected by stale arrival writes. A fresh request starts a separate cycle and clears old arrival/travel state.
- New requests retain the existing five-minute deadline. Acceptance establishes the existing twelve-hour meetup window. Client arrival/focus timers now agree with that window; the legacy fifteen-minute client expiry is removed.
- `sweepMeetupAutoClose` runs every five minutes and checks the stored deadline in a transaction, including accepted meetups. Legacy documents without deadlines get a creation-based fallback. Pagination avoids starving older documents behind the first 300 results. Two saved arrivals become completed; otherwise the session becomes unanswered/unfinished. Scheduler or network outages can delay closure until service resumes.
- `onMeetupOutcome` writes idempotent, owner-only `users/{uid}/meetupOutcomes` receipts for terminal transitions. These contain outcome and date, without peer identity or coordinates, and survive cleanup of temporary meetup documents. The history screen displays recent outcomes. Existing historical terminal documents are not backfilled by this change.
- An unfinished meetup receives no completion credit. There is no automatic no-show accusation or trust deduction: a timeout alone cannot establish which participant was responsible. Safety exits remain neutral.

## Rollout and validation

Deploy the new `endMySafetySession` and `onMeetupOutcome`, updated `sweepMeetupAutoClose`, `onMeetupTransitionGuard`, `onChatGateTransitionGuard`, and `onNewChatMessage`, plus Firestore rules before distributing the new clients. Include the pending Party/feedback backend functions documented in `meetup_party_feedback.md`. Existing completion accounting and interaction-lock projection must remain deployed. No new composite index is needed for the new queries.

Automated coverage includes authenticated and concurrent cancellation, closed-chat rules, immutable outcomes, scheduler pagination, group exits, outcome receipts, visible guidance, and two-tap emergency access over a modal. Physical Android/iOS dialer handoff, notification delivery, accessibility, external Maps return, and two-device completion/cancellation still need device verification. Automated tests use an injected phone launcher and never place an emergency call.

Validation: Flutter suite 222 passed / 3 existing skips; backend and Firestore/Storage emulator suites 69 passed; Flutter analysis clean; iOS simulator compile passed. All required functions are active and all nine indexes are ready. The scheduled meetup cleanup has run successfully. Generated logs remain under ignored `artifacts/release/`.
