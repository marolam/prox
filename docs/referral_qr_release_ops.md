# Referral QR Release Ops Checklist

Purpose
- Keep one stable QR referral endpoint while always serving latest Android and iOS targets.
- Preserve referral tracking and tree attribution fields for every click and install flow.

Current endpoint behavior
- Endpoint: referralApkDownload
- Platform routing:
  - Android user-agent redirects to Android target URL.
  - iOS user-agent redirects to iOS target URL.
- Tracking preserved on redirects:
  - referrerUid
  - rootReferrerUid
  - code or token
  - clickId and lead records

One-time setup
1. Ensure QRs point to the stable referral endpoint URL (not direct APK URL).
2. Ensure iOS destination is one of the allowlisted hosts:
   - apps.apple.com
   - testflight.apple.com
   - prox-us.com
   - www.prox-us.com
3. Ensure Android destination is a valid GitHub releases APK URL.

Environment keys used by referral routing
Android target selection order
1. PROX_REFERRAL_ANDROID_URL
2. PROX_PUBLIC_APK_URL
3. apk query hint if allowlisted
4. PROX_PUBLIC_APK_FALLBACK_URL
5. default public APK URL in code

iOS target selection order
1. PROX_REFERRAL_IOS_URL
2. PROX_IOS_UPDATE_URL
3. PROX_IOS_UPDATE_FALLBACK_URL
4. PROX_IOS_FALLBACK_URL

Per-release update steps
1. Publish Android build asset to GitHub release.
2. Update environment to latest targets:
   - PROX_REFERRAL_ANDROID_URL to latest public APK release URL
   - PROX_REFERRAL_IOS_URL to latest App Store or TestFlight URL
3. Keep fallback keys populated for resilience:
   - PROX_PUBLIC_APK_FALLBACK_URL
   - PROX_IOS_UPDATE_FALLBACK_URL or PROX_IOS_FALLBACK_URL
4. Verify endpoint behavior using sample referral links on both platforms.

Validation checklist
1. Android request to referral endpoint returns 302 to APK URL with referral params.
2. iOS request to referral endpoint returns 302 to iOS URL with referral params.
3. Missing iOS URL returns explicit safe error ios_url_not_configured.
4. referralDownloadClicks and referralDownloadLeads records include referrerUid/rootReferrerUid and token or code.
5. New-user attribution finalization still succeeds after first authenticated app open.

Download target synchronization
- `tools/scripts/sync_release_download_targets.ps1` updates the primary and
  higher-priority referral override together, including platform fallbacks.
  Previously, an old `PROX_REFERRAL_ANDROID_URL` or `PROX_REFERRAL_IOS_URL`
  could keep QR downloads on an older build despite updating the public URL.
- Use `-Platform android` for an Android-only release, `-Platform ios` after
  Apple availability is confirmed, or `-Platform both` for a ready paired release.
  Unselected platform keys and the gated `PROX_GROWTH_*` pilot URLs are preserved.
- A pinned production APK target is supported while the website keeps its stable
  `/releases/latest/download/app-release.apk` entry point.
- `-SkipDeploy` prepares local environment values only; it does not change the
  live endpoint. An incomplete Functions source tree fails rather than reporting
  a successful sync without deployment.
- The QR release check uses a non-consuming Android HEAD probe when a real code
  is supplied, and compares the redirect with `-PublicApkUrl`. Without `-Code`,
  only the APK download is verified, not live referral routing.
- Offline regression checks:
  `powershell -ExecutionPolicy Bypass -File .\tools\scripts\test_release_download_targets.ps1`.

Attribution, credit, and relationship boundaries
- Code-only links resolve their owner on the server, never from a `ref` hint.
  They remain compatible for existing accounts but do not unlock new accounts.
- Direct referrers and root ancestry are separate. Code acceptance, growth
  invitations and short-lived QR tokens preserve the inviter's server-owned
  root ancestry. Rewards still go to the direct eligible participants, not to
  every ancestor.
- Growth welcome/referrer credits use their own idempotent reward receipts.
  Suspicious accounts remain held for review. The legacy verified five-meetup
  milestone is separate and is not granted by downloading an APK.
- New Auth accounts require server-owned `referralTrustRequired` and
  `referralInPersonVerified` state. Accounts already present before this rollout
  are not retrospectively locked; a separate reviewed migration is needed.
- Every new single-use QR requires precise inviter location. Missing, remote,
  inaccurate or expired recipient verification rejects acceptance without
  consuming the token or assigning a referrer. Ordinary/growth codes cannot
  establish trust. New users may finish their profile and contact support while
  matching, chats and recruiting remain gated.
- The immutable direct referrer defaults to an informal mentor, not official
  support. Only that direct referrer can read each private progress projection
  and send a usage/support nudge. Ancestors and other Party members cannot.
  Private mentor summaries are individually readable, not list-queryable, so
  blocking immediately revokes access even before projection cleanup runs.
- Mentor reminders are server-authorized, deduplicated and share a 12-hour
  cooldown. Push delivery is not guaranteed; reminders persist in the new user's
  mentor card, including when they have no registered device.
- Optional Party addition waits for profile completion and in-person proof,
  respects QR consent, removal, blocking and deletion. The mentor remains easily
  available in a dedicated Party card unless blocked or deleted; attribution
  does not force renewed contact. Unverified legacy mentor contacts do not count
  toward trusted matching or expose Party-private profiles.
- Growth referrer credit requires a server-verified completed meetup after
  referral acceptance, never signup/profile/chat alone. Legacy five-meetup credit
  is unchanged. Existing historical credits are not clawed back.

Abuse controls and moderator operations (local implementation; not deployed)
- Account moderation is available to Firebase `admin`-claim operators from
  Tester operations. Suspend immediately to investigate; restore after review;
  irreversible deletion requires confirmation and erases account data.
- `moderateAccount` requires the bound administrator UID, target UID, reason and
  stable request ID. It refuses self-moderation and other administrators. Every
  action has a server-owned audit receipt; failed actions remain restricted and
  must be retried with the same ID. Deleted accounts cannot be restored.
  Use "Load status / recover pending action" after closing the screen or
  restarting the app; the initiating administrator can recover the original
  server-persisted request rather than inventing a new ID.
- `accountEnforcements` blocks cached Firestore/Storage tokens immediately.
  Suspension also disables Firebase Auth and revokes refresh tokens. Matching
  and discovery exclude disabled/banned accounts. Client writes cannot change
  enforcement, disable/ban flags or referral trust.
- Callable APIs share a transactional 120-requests-per-user-per-minute budget.
  Existing invite, reward, support, Party-code and nudge budgets remain in place.
  Support recovery, subscription cancellation and self-deletion are preserved.
- Native App Check already activates Play Integrity on release Android and
  DeviceCheck on release iOS. Set `PROX_ENFORCE_APP_CHECK=true` for guarded
  callables only after registering the apps/providers, testing legitimate
  release/store and approved debug clients, and observing App Check metrics.
  Also configure Firestore/Storage enforcement in Firebase; callable enforcement
  does not secure direct database access. The flag affects all clients of those
  endpoints, including web; web currently skips App Check activation. Keep
  enforcement off until web has an approved provider or its API access is
  intentionally restricted. No live enforcement setting has been changed.
- GPS proximity and attestation are signals, not proof against every spoofed
  location, colluding users, burner identity or compromised device. Reports,
  blocks, reward holds and human review remain essential. Retained financial and
  moderation receipts must follow the published privacy/retention policy.

Read-only live audit (October 8, 2026)
- Public production latest is `0.19.0+26`; its canonical APK is downloadable.
- The Android update condition still targets `0.19.0+23`, including a pinned
  build-23 URL. Users are not currently forced to production build 26 by that
  policy. Advancing it requires a reviewed activation; this audit does not deploy.
- Growth invitation configuration intentionally targets the separately gated
  `0.20.2+29-staging` APK, not production latest. Do not silently promote this
  pilot or make production users follow its prerelease.
- The live iOS policy contains a placeholder TestFlight URL. A real available
  iOS destination and verified build are required before policy activation.
- The protected remote `v1.0` rollback digest passes. The local canonical APK
  differs from that rollback digest; the full local rollback check does not pass.

Production release preparation (October 9, 2026)
- The approved package version is `0.21.0+30`, newer than both published
  production `0.19.0+26` and the phones' installed `0.20.2+29`.
- At preparation start this was a source version bump, not a publication.
  Download targets and policy were held until package and backend verification.
- Release preparation restored the local rollback reference from the exact
  protected `v1.0` bytes after preserving the previous local APK separately.
  The remote release was not overwritten, and the full safety gate passed.
- Backend release audits required patched `proxy-addr` 2.0.8 in both codebases
  and `@fastify/busboy` 3.2.2 in the main codebase. Both dependency trees now
  report no known vulnerabilities; dependency changes are limited to these fixes.
- Leave both phones on their current packages to verify the ordinary production
  update gate, download and user-approved installation rather than USB delivery.
- Continue patch versions and build numbers monotonically for later candidates.
  Do not reuse a published version/build or replace the protected rollback.

Verified production publication (October 9, 2026)
- Published `v0.21.0+30` as the stable GitHub latest release from commit
  `2f216d9c83318ae3c748a1f43075029254754e66`. Paired workflow
  `37883374643` completed successfully.
- Android APK SHA-256:
  `af11a7b00ff99ecf2e6a88e8aa0369e2a77d331fda66c512d51545de5af95f25`.
  Package `com.prox.app`, version `0.21.0`, build `30`, signing identity and
  manifest size/hash were verified. Anonymous pinned and permanent latest
  downloads serve identical verified bytes.
- iOS IPA SHA-256:
  `b9ef133ef01647f2ff4ecdf77522a90fc2d697580621d90e43a77b5d7350cb82`.
  Bundle `com.prox-us.prox`, version/build and manifest size/hash were verified.
  TestFlight upload succeeded. Apple processing, tester availability and
  App Store publication were not verified; no new iOS mandatory policy was
  activated without a valid available installation destination.
- Backend functions, Firestore/Storage rules and indexes deployed successfully.
  The matching index is `READY`; legacy `licenseApi` was preserved.
  Validation passed: clean Flutter analyzer, 428 Flutter tests (3 skipped),
  221 backend emulator tests, 24 release Python tests and offline policy tests.
  Both backend dependency audits reported zero vulnerabilities.
- Remote Config version `20` activates Android latest/minimum `0.21.0+30`,
  including the legacy Android condition. Mandatory minimum and force-latest
  are enabled, with a pinned build-30 APK URL. Existing build-29 source also
  honors this explicit minimum even for tester packages.
- Ordinary referral HEAD verification passed without consuming an invitation.
  The growth pilot Android target was intentionally promoted to production
  latest, and only `referralApkDownload` was redeployed for that target change.
  No active, unexpired growth invitation was available for a live growth HEAD
  probe. The live download endpoint is `ACTIVE`, and its ordinary, fallback
  and growth Android target variables were separately verified as production
  latest, which resolves to the same verified build-30 APK as the updater.
- Both phones were left on their existing packages for ordinary-user update
  delivery. Opening online should fetch the mandatory gate; Android still
  requires user approval to install. On-device gate/install UX remains pending
  user observation; no USB install, downgrade or app-data clearing was done.
- Protected `v1.0` and the local canonical rollback digest passed verification
  again after publication. New release assets are stored separately.

Operational notes
- Keep QR payload stable over time; rotate only environment values per release.
- Do not hardcode direct APK links into user QR payloads.
- For iOS production distribution, use App Store or TestFlight destination URLs.

Relevant implementation files
- functions/src/referral_downloads.ts
- lib/services/referral_attribution.dart
- functions/test/backend.test.cjs
