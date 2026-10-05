# Prox growth candidate release audit — 2026-10-05

This audit covers the `0.20.0+27` paired staging candidate. The selected backend deployment is complete and verified; native app publication remains pending. The preserved source and live backend baseline are described in [growth_rollback.md](growth_rollback.md).

## Verified status

The read-only backend verification completed at `2026-10-05T11:59:52.439Z` for `prox-42bef`: all **48 selected functions** were ACTIVE and passed readiness/IAM checks, including the **28 expected public invoker permissions**. Reviewed Firestore and Storage rules matched their live releases, all **12 declared composite indexes** were READY, and all **21 declared field overrides** passed, including **9 ACTIVE TTL policies**. Dashboard metrics were current at verification, with server `updatedAt` `2026-10-05T11:38:51.980Z`. The existing `licenseApi` and production Remote Config were preserved. Private evidence is retained in `artifacts/release/growth-0.20.0-27-verification-with-offers/deployment-verification.json` and excluded from publication.

Both backend TypeScript builds passed, the final complete Firestore/Storage/backend emulator suite passed **166/166** without skips, and both backend dependency audits reported zero vulnerabilities. The final `0.20.0+27` app analyzer found no issues and the complete Flutter regression passed **366 tests with 3 existing skips**. The final Android debug APK compiled and was installed on the test phone. Signed paired release artifacts, GitHub staging publication and TestFlight availability remain pending. Backend deployment and debug installation do not assert native app publishing completion.

## Source and distribution

The preserved pre-growth HEAD is `42361b569260718b37a8ce481894566e8bd5ab25` on `release/meetup-safety-21`. The candidate is now on `release/growth-0.20.0-27`, and `pubspec.yaml` declares `0.20.0+27`. Commit the complete reviewed candidate before pushing, including the preserved necessary changes. The older release branch remains a separate baseline.

Include the existing tracked modifications/deletions and all necessary untracked Dart, TypeScript, Kotlin, resource, test, recovery-script, and operational-document sources. Review the staged path list and diff before committing. Exclude logs, generated build outputs, generated Linux plugin files, screenshot backup directories, temporary analysis artifacts, local environment files, signing keys, signing profiles, and all protected rollback artifacts. The existing `.gitignore` protects local environment/signing files and `artifacts/`; ordinary top-level `*.log` files are still untracked and require explicit exclusion.

The paired workflow requires staging source on `release/*`. Its resolved staging inputs are:

| Field | Value |
| --- | --- |
| Native app version/build | `0.20.0+27` |
| Release tag | `v0.20.0+27-staging` |
| Android asset | `app-release-staging.apk` |
| iOS asset | `app-release-staging.ipa` |
| Android install URL | `https://github.com/marolam/prox/releases/download/v0.20.0%2B27-staging/app-release-staging.apk` |
| TestFlight | Enabled; App Store export |
| Tester build | Enabled |
| Public iOS install URL | Optional; may remain empty for invite-only TestFlight |

The workflow verifies both native package IDs and version/build, the existing Android signer, and checksums. It publishes the complete asset pair as a GitHub prerelease with `--latest=false`, then anonymously verifies the version-pinned APK bytes. Staging never activates production Android Remote Config; iOS policy preparation is optional and activation remains separate.

The live GitHub latest release remained `v0.19.0+26`, with Android SHA-256 `5440bedf65adbd3a067aa004ea30e824f252d4ad53076b5613597630391d9a31`. Repository secret names cover Android/iOS signing and App Store Connect upload, and the Android signer variable exists. Secret-name presence does not verify signing material validity or Apple processing/availability. The staging GitHub environment has no required reviewer or wait timer at audit time.

Upload success to App Store Connect is not proof that testers can install the build. Report Apple processing, external review, or tester availability as pending until verified. If TestFlight upload succeeds and later GitHub publication fails, report the partial distribution explicitly. Android device smoke testing also remains separate from compilation and package verification.

## Selected backend deployment

The same Firebase project serves existing production clients. A staging APK/IPA does not isolate these backend changes. Keep growth in its default `testers` stage with administrator approval and capacity 20 until the first tester phase is complete.

Use individual function filters with explicit project `prox-42bef`. The original private `deployment-targets.json` contains **43 unique targets: 40 in `default` and 3 in `notifications`**. The five reviewed offer targets below were deployed separately and included through the verifier's additional-targets input, bringing the verified total to **48: 45 in `default` and 3 in `notifications`**. These cover growth, legacy support normalization, referral transport, account cleanup, preserved feedback rewards, background matching, meetup accounting, business follow-up, dashboard metrics, business activation, notification changes and real moderated offers. See [business_offers_operations.md](business_offers_operations.md) for the offer workflow and limits.

```text
getGrowthStatus
joinTesterCohort
createGrowthInvite
acceptGrowthReferral
syncGrowthProgress
recordGrowthSession
submitGrowthSupport
replyToSupportTicket
updateSupportTicket
getGrowthOps
reviewGrowthReward
reviewTesterApplication
updateGrowthConfig
onGrowthAuthCreate
onGrowthProfile
onGrowthChatMessage
onGrowthMeetupReceipt
recomputeGrowthDailyMetrics
onLegacyFeedbackSupport
onLegacyBugReportSupport
onLegacySupportTicket
backfillLegacySupport
createReferralSingleUseToken
referralApkDownload
finalizeReferralSingleUseToken
linkReferralCode
deleteMyAccount
onAuthDelete
claimVerifiedReward
onBackgroundPresence
onBackgroundMatchAlert
getBackgroundOpportunity
listBackgroundOpportunities
onMeetupCompletedAccounting
syncCompletedMeetup
onBusinessAutomationWritten
runBusinessFollowupAutomation
configureBusinessAutomation
recomputeDashboardMetrics
setBusinessModeActive
upsertBusinessOffer
changeBusinessOfferState
reviewBusinessOffer
listPublicBusinessOffers
onBusinessOfferAccountDeleted
```

The 45 names above use `functions:default:<name>`; the last five are the separately deployed offer targets. The remaining three filters are:

```text
functions:notifications:onMeetupStatusNotification
functions:notifications:onPartyNetworkInsightRequest
functions:notifications:onKeywordReportCreated
```

`createReferralSingleUseToken`, `referralApkDownload`, and `finalizeReferralSingleUseToken` were absent from the 39 live functions despite being present in the preserved local source. The new referral link/QR flow needs their explicit deployment. `restrictedApkDownload` is already live and its handler has no candidate behavior change. Existing `onReferralMilestoneReward`, `onSupportTicketReward`, `onPointsProgressionWrite`, and `onAuthCreate` effective source matches their live baseline; these do not need redeployment for this change.

Avoid a broad functions deployment: live `licenseApi` is absent from the candidate default entry point. The three selected notification handlers belong to the separate `notifications` codebase and require the explicit filters above. A full default deployment could propose deleting an unrelated live function. Preserve existing IAM and runtime configuration. A private comparison of the local environment against the originally selected existing functions found identical common values; only four referral Android/iOS/fallback configuration keys were added locally. No secret values are included in this audit.

Preexisting local meetup guards, auto-close behavior, no-show penalties, point-store catalogs, and external card purchase code also differ from their captured live source versions. They are preserved in the candidate source but their unrelated handlers remain outside this selected deployment. The two meetup accounting handlers are explicitly included. Any further core behavior change requires its own test evidence and release accounting.

The four background matching handlers were absent from the captured production baseline and are included in the 48 selected targets. `PROX_BACKGROUND_MATCHING_AVAILABLE` remains false by default. The paired workflow offers an explicit staging-only Android background option; iOS keeps the disabled default. Backend index readiness is verified; enabling the Android option still requires physical-device background verification. iOS physical background behavior has not been verified and remains gated off. The background read service/screens bind responses to the opening UID, clear cached details when the account changes, and send an enforced `expectedUid`; corresponding async/widget/callable regressions were added.

Native availability now mirrors the Flutter build definition: Android decodes Flutter's `dart-defines` into a `BuildConfig` boolean; iOS reads the Xcode-expanded `DART_DEFINES` from a dedicated Info.plist key and accepts only the explicit true availability definition. Missing/invalid definitions fail closed. Disabled native builds stop collection and clear only their dedicated persisted collector preferences, including Android boot/package-update and iOS native restoration paths. Fresh installations default to native opt-out. Verify disable, account change, location revocation, locked-phone updates, and notification delivery on the candidate device; iOS compilation and device behavior require separate verification. An old baseline binary cannot acquire this new gate; see the explicit rollback preparation in [growth_rollback.md](growth_rollback.md).

## Rules and indexes

The captured pre-growth Firestore rules match the actual live Firestore rules exactly after normalizing line endings. Candidate Firestore changes protect server-owned growth rewards and ops data, add private support replies, validate legacy reporter aliases, and keep growth-generated referral codes and support workflow updates server-owned. These are growth/support changes.

The preserved pre-growth Storage rules already differ from live in two ways: they deny accounts with an `accountDeletions` marker and narrow `image/*` uploads to JPEG/PNG/WebP/GIF. The candidate adds private `supportAttachments` uploads limited to 5 MiB and JPEG/PNG/WebP. The profile photo writer uses `image/jpeg`, which remains supported. Other arbitrary image types such as HEIC, AVIF, or SVG would be rejected by the preserved hardening. Include these differences when reviewing the Storage deployment and its rollback.

All 9 baseline live composite indexes and 8 baseline configured field overrides are represented in the candidate declaration; no unrelated live indexes were deleted. Verification now confirms all 12 candidate composites READY, including the new `messages` index (`from` ascending, `ts` descending) and business automation index. The `rewardClaims.inviteeUid` collection-group field index and all 21 configured field overrides passed, including 9 active TTL policies. Growth TTL fields are additive. A background-presence composite and background TTL/index overrides were already present in the preserved local source but are also new relative to the production baseline. Offers use single-field private queries and document-ID public paging and need no additional composite index.

## Verification before reporting completion

1. Verify the protected source, backend configuration, exact APKs, database snapshot restore evidence, and private Storage backup using the recovery documentation.
2. Commit/push the complete candidate source on the new release branch; confirm CI uses that exact commit.
3. Completed for app/backend: clean analyzer, 366 passing app regressions with 3 existing skips, 166/166 Firestore/Storage/backend emulator tests, both TypeScript builds and zero-vulnerability backend dependency audits. Complete remaining release-script and paired distribution checks before publication.
4. Completed: deploy only reviewed rules/index changes and explicit backend targets. All 48 selected functions, indexes, function readiness/IAM and growth configuration passed verification; the five offer handlers were reviewed and deployed separately. Existing unselected core handlers and production Remote Config retain their baseline state.
5. Run paired staging CI. Verify signed APK/IPA version `0.20.0`, build `27`, published prerelease asset digests, anonymous APK access, public latest still `v0.19.0+26`, and unchanged production policies.
6. Verify installation and the tester mission, referral-stage guard, support submission/reply, screenshot access, account switching, and core actions on supported devices. Identify unavailable device/Apple checks honestly.
7. Follow `AGENTS.md`: report publishing complete only after verification, including version/build, significant changes, platforms/channels, and any pending portions.
