# Growth pilot hotfix: 0.20.1, build 28

The Dashboard snapshot could throw `Bad state: Stream has already been listened to` after its Party card scrolled offscreen and returned. The same retained private stream could fail when switching Offers tabs. Each listener now has independent account and data subscriptions; cancelled, queued and paused events cannot reveal a previous account's records.

Treasure Compass now waits for the actual approved Party snapshot when ranking Party-scoped matches. It previously consumed the empty account-reset event before membership loaded.

Support forms now distinguish validation, account, rate-limit and uncertain-delivery errors without displaying private server diagnostics. A rejected first attempt allows editing while retaining its report ID. After an uncertain attempt, retries retain the exact original payload, including after a later rejection. Saved drafts are removed only after confirmed submission. Existing short drafts retain their IDs, categories and automatically collected metadata.

Both rollback checkpoints remain preserved: the full pre-growth source/backend/data recovery baseline and `artifacts/rollback/hotfix27-pre-fix-20261005T132543511961Z`, containing the exact published build-27 APK and source references.

The supplied support screenshot matches the manual-metadata form in known build-26 binaries. Its installed version and exact failed request are unverified. Current backend compatibility checks accepted that older client's short `test` subject/message and same-ID replay; this hotfix does not weaken support security rules.

Local validation passed: analyzer clean; full Flutter regression 384 passed with 3 existing skips; final support checks 16 passed; release automation 24 passed. The full paired CI must repeat app/backend checks on the frozen source before publication.

Distribution verification is pending until the paired staging run and Apple processing complete. Public latest remains build 26. Physical Android retesting is pending while the test phone is disconnected, and physical iOS testing remains pending. External TestFlight review and real founding-tester recruitment remain operator steps.
