# Prox growth candidate release audit — 2026-10-05

The subsequent [0.20.1, build 28 hotfix](growth_hotfix_20261005.md) is now the latest verified paired staging release and internal TestFlight build. It repairs Dashboard/Offers stream remounts, approved Party matching and support draft/retry/account cleanup. The build-27 audit below remains historical evidence for the full growth implementation; public latest remains build 26.

This audit covers the published `0.20.0+27` paired staging release. The selected backend deployment, Android/iOS GitHub publication, and internal iOS TestFlight availability are complete and verified. External TestFlight beta submission/review and real cohort recruitment remain operator steps. The preserved source and live backend baseline are described in [growth_rollback.md](growth_rollback.md).

## Verified status

The final read-only backend verification for `prox-42bef` passed after publication: all **48 selected functions** were ACTIVE and passed readiness/IAM checks, including the **28 expected public invoker permissions**. Reviewed Firestore and Storage rules matched their live releases, all **12 declared composite indexes** were READY, and all **21 declared field overrides** passed, including **9 ACTIVE TTL policies**. Dashboard metrics were fresh, with server `updatedAt` `2026-10-05T13:14:20.116Z`. Both hourly metric jobs also completed an automatic scheduled run before the final manual refresh. The existing `licenseApi`, all 39 baseline handlers' existing environment values/secret references, and complete production Remote Config were preserved. Private evidence is retained in `artifacts/release/growth-staging27-final-published-live-proof/deployment-verification.json` and excluded from publication.

Both backend TypeScript builds passed, the complete Firestore/Storage/backend emulator suite passed **166/166** without skips in local and required CI validation, and both backend dependency audits reported zero vulnerabilities. The final `0.20.0+27` app analyzer found no issues and the complete Flutter regression passed **366 tests with 3 existing skips**. Paired CI repeated the full app and release-policy checks on macOS, built both signed native packages, verified their versions/Android signer, and completed publication successfully. The final Android debug APK was installed on the test phone; the authenticated upgrade–rollback–upgrade drill and real private support screenshot/reply flow were verified. The final dialog fix passed widget regressions; the phone was later disconnected, preventing a further physical recheck. Physical iOS behavior remains a separate check.

The [staging release](https://github.com/marolam/prox/releases/tag/v0.20.0%2B27-staging) was published at `2026-10-05T13:12:29Z`. Independent anonymous downloads verified both packages against the exact CI manifest, and the downloaded APK passed native version/package and cryptographic signing checks with the existing release certificate. The anonymous public latest APK still matches the exact build-26 baseline.

| Package | Bytes | SHA-256 |
| --- | ---: | --- |
| `app-release-staging.apk` | 84,179,193 | `9707df20c52b2777be2ab97d810b4451f907fa71fdbe534d048dcada90f4ae47` |
| `app-release-staging.ipa` | 55,509,494 | `b28fa5d20ce11ac821005f36dff47fabcdb67e3bc9556fc1c566f334ecc588dc` |

Private download proof is in `artifacts/release/growth-staging27-public-verified-20261005T1314/`. The [read-only Apple inspection 37315701925](https://github.com/marolam/prox/actions/runs/37315701925) completed successfully and observed build **27**, version **0.20.0**, `processingState=VALID`, `expired=false`, and `internalBuildState=IN_BETA_TESTING`, assigned to the internal **Prox Testers** group. Internal TestFlight availability is verified. External state is `READY_FOR_BETA_SUBMISSION`; external review has not been submitted/approved and no public TestFlight join link is enabled. Private evidence is `artifacts/release/testflight-after-staging27-second.json`.

## Source and distribution

The preserved pre-growth HEAD is `42361b569260718b37a8ce481894566e8bd5ab25` on `release/meetup-safety-21`. The candidate is committed and pushed on `release/growth-0.20.0-27`, and `pubspec.yaml` declares `0.20.0+27`. The frozen application source is `0f6cb8b223c06fde22c0fc706f55690269b37801`, used by [paired staging run 37309608632](https://github.com/marolam/prox/actions/runs/37309608632). The older release branch remains a separate baseline. Documentation updated after the build does not change the artifact's source commit.

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

This distributed pilot preserves the existing Pro/Business rollout gates: `PROX_ENABLE_BUSINESS_MODE=false`, `PROX_BUSINESS_MODE_FORCE_OFF=true`, and `PROX_PRO_MODE_PREVIEW_ENABLED=false`. Personal Big 5, growth/support, local-offer browsing, and administrator offer review remain available. Paid-owner HQ, leads, storefront, insights, and offer creation are implemented but require a separately enabled, validated Pro rollout. Android and iOS background matching are both disabled in this paired build. Owner follow-up reminders and customer outbound providers remain disabled until explicitly configured through the documented operations controls.

Once Apple accepts staging build 27, the next uploaded production/recovery package must use a new build number above 27; a different GitHub channel does not permit reusing an App Store Connect build number.

The live GitHub latest release remained `v0.19.0+26`, with Android SHA-256 `5440bedf65adbd3a067aa004ea30e824f252d4ad53076b5613597630391d9a31`. Repository secret names cover Android/iOS signing and App Store Connect upload, and the Android signer variable exists. Secret-name presence does not verify signing material validity or Apple processing/availability. The staging GitHub environment has no required reviewer or wait timer at audit time.

Upload success to App Store Connect is not proof that testers can install the build. Report Apple processing, external review, or tester availability as pending until verified. If TestFlight upload succeeds and later GitHub publication fails, report the partial distribution explicitly. Android device smoke testing also remains separate from compilation and package verification.

## Selected backend deployment

The same Firebase project serves existing production clients. A staging APK/IPA does not isolate these backend changes. Keep growth in its default `testers` stage with administrator approval and capacity 20 until the first tester phase is complete.

The October 5 live operations check found no approved tester members and no pending applications. The software is ready for operator selection of 10–20 real nearby people; it does not claim they have been recruited or activated. Have each person apply under Settings → Founding tester rewards, then approve them in Tester operations when their testing partners are ready. Approval starts the 48-hour mission. Use Support & feedback as the single feedback channel and assign a person to reply the same day. See [founding_tester_operations.md](founding_tester_operations.md) for qualification, stage progression, rewards, and the five metric definitions.

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

Native availability now mirrors the Flutter build definition: Android decodes Flutter's `dart-defines` into a `BuildConfig` boolean; iOS reads the Xcode-expanded `DART_DEFINES` from a dedicated Info.plist key and accepts only the explicit true availability definition. Missing/invalid definitions fail closed. Disabled native builds stop collection and clear only their dedicated persisted collector preferences, including Android boot/package-update and iOS native restoration paths. Fresh installations default to native opt-out. Actual Android locked-phone collection, disable, native service stop, server presence removal and permission restoration were verified in the opt-in debug candidate. Multi-device alert delivery and physical iOS background behavior remain pending; signed iOS compilation passed. Both distributed pilot packages keep background matching disabled. An old baseline binary cannot acquire this new gate; see the explicit rollback preparation in [growth_rollback.md](growth_rollback.md).

## Rules and indexes

The captured pre-growth Firestore rules match the actual live Firestore rules exactly after normalizing line endings. Candidate Firestore changes protect server-owned growth rewards and ops data, add private support replies, validate legacy reporter aliases, and keep growth-generated referral codes and support workflow updates server-owned. These are growth/support changes.

The preserved pre-growth Storage rules already differ from live in two ways: they deny accounts with an `accountDeletions` marker and narrow `image/*` uploads to JPEG/PNG/WebP/GIF. The candidate adds private `supportAttachments` uploads limited to 5 MiB and JPEG/PNG/WebP. The profile photo writer uses `image/jpeg`, which remains supported. Other arbitrary image types such as HEIC, AVIF, or SVG would be rejected by the preserved hardening. Include these differences when reviewing the Storage deployment and its rollback.

All 9 baseline live composite indexes and 8 baseline configured field overrides are represented in the candidate declaration; no unrelated live indexes were deleted. Verification now confirms all 12 candidate composites READY, including the new `messages` index (`from` ascending, `ts` descending) and business automation index. The `rewardClaims.inviteeUid` collection-group field index and all 21 configured field overrides passed, including 9 active TTL policies. Growth TTL fields are additive. A background-presence composite and background TTL/index overrides were already present in the preserved local source but are also new relative to the production baseline. Offers use single-field private queries and document-ID public paging and need no additional composite index.

## Verification before reporting completion

1. Verify the protected source, backend configuration, exact APKs, database snapshot restore evidence, and private Storage backup using the recovery documentation.
2. Completed: candidate source committed/pushed; successful paired CI and the published manifest/tag identify exact commit `0f6cb8b223c06fde22c0fc706f55690269b37801`.
3. Completed: clean analyzer, 366 passing app regressions with 3 existing skips, 166/166 Firestore/Storage/backend emulator tests, both TypeScript builds, zero-vulnerability backend dependency audits and required release-script/update-policy checks.
4. Completed: deploy only reviewed rules/index changes and explicit backend targets. All 48 selected functions, indexes, function readiness/IAM and growth configuration passed verification; the five offer handlers were reviewed and deployed separately. Existing unselected core handlers and production Remote Config retain their baseline state.
5. Completed: paired staging CI, signed APK/IPA version `0.20.0`, build `27`, both anonymous package downloads/digests, public latest still `v0.19.0+26`, unchanged complete production policies, and Apple VALID/internal Prox Testers availability. External TestFlight submission/review remains pending.
6. Verify installation and the tester mission, referral-stage guard, support submission/reply, screenshot access, account switching, and core actions on supported devices. Identify unavailable device/Apple checks honestly.
7. Follow `AGENTS.md`: report publishing complete only after verification, including version/build, significant changes, platforms/channels, and any pending portions.
