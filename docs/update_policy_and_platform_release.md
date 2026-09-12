# Update policy and paired platform releases

For the current tag-triggered workflow, required CI credentials, automatic Android
policy activation and TestFlight upload defaults, see
[Automatic paired releases](automatic_paired_releases.md). The historical audit
and migration details below describe the earlier build 19 rollout.

The app automatically checks its installed package version at launch, on resume,
on a bounded polling schedule, and when Firebase Remote Config announces an
update. Login, settings and the gate share an in-flight request and a short cache.
Mandatory updates cover every app route and preserve the current screen's state.
Previously activated mandatory policies still apply when a refresh is offline.

Remote Config is authoritative. GitHub tags are release labels, not reliable
installed versions: the protected `v1.0` rollback does not mean its package is
newer than `0.18.8+18`. Checking an update no longer downloads APKs or sends each
device to GitHub's unauthenticated API. iOS never uses an Android APK link or a raw
IPA as its install destination.

## Policy keys

| Key | Meaning |
| --- | --- |
| `update_latest_version` | Latest common installed version, including numeric build when known |
| `update_minimum_required_version` | Oldest supported common installed version |
| `update_force_latest_enabled` | Require latest in production release builds |
| `update_minimum_required_enabled` | Enforce the explicit compatibility floor, including tester builds |
| `update_important_enabled`, `update_important_min_version` | Dismissible important-update reminder |
| `update_check_enabled` | Disable remote update prompts and gates when false |
| `update_download_url` | Android HTTPS install destination |
| `update_download_url_ios` | iOS App Store or TestFlight HTTPS destination |
| `update_minimum_required_notes` | Explanation displayed on the mandatory gate |
| `update_poll_minutes` | Polling interval, clamped to 5–240 minutes |

Version and boolean policy keys support `_android` and `_ios` suffixes. An
explicit platform value overrides the shared value. When disabling a gate in the
Firebase console, update the applicable platform override as well as any shared
value. A valid `PROX_MIN_REQUIRED_VERSION` compiled into the app is an independent
floor when `PROX_ENFORCE_MINIMUM_VERSION=true`.

Versions are strictly validated. Malformed remote strings do not lock users out.
Unknown installed versions and offline checks report that verification failed
instead of claiming the app is current. Missing build numbers are not invented:
`0.18.8` and `0.18.8+18` compare equally; `0.18.8+19` is newer than `0.18.8+18`.
Prerelease ordering follows semantic version precedence.

## Prepare and activate a release

`sync_release_remote_config.ps1` defaults to **Android only**, so an APK release
cannot advance the iOS gate during store review. Its offline preparation mode
requires no Firebase login and does not deploy anything:

```powershell
./tools/scripts/sync_release_remote_config.ps1 -PrepareOnly `
  -LatestVersion 0.18.8+18 -Platform android `
  -OutputPath artifacts/release/android-update-policy.parameters.json
```

For a paired policy, use `-Platform both` and the actual installable
`-IosDownloadUrl`. Both platforms then receive the same latest and minimum
version; shared keys are also advanced for older clients. The prepared JSON is a
parameter patch for review, not a complete replacement Remote Config template.
After both platform builds are available to all intended users, running the
script without `-PrepareOnly` fetches the current template, applies those
parameters and deploys Remote Config. Existing conditional overrides are
preserved and must be reviewed if they target a different release cohort.

Existing build 18 reads the shared `update_*` keys and ignores the new Android
suffixes. An Android-only migration can explicitly opt in to
`-IncludeLegacyAndroidPolicy`. This mode writes both sets of keys as conditional
values under `prox_legacy_android_update_policy`, with this Firebase condition:

```text
app.id == '1:12575732319:android:c5ec68ebc2de45de5561ea'
```

The script resolves the ID from `android/app/src/release/google-services.json`,
checks its project against `-ProjectId`, and matches its package to the Gradle
`applicationId`. It sets the legacy and Android-specific minimum version and
minimum-enabled flag, so tester builds that bypass force-latest can still enforce
the explicit minimum. Every existing default, iOS parameter, unrelated condition,
conditional value, and parameter group is preserved. The owned Android condition
has highest priority for these update keys; existing Android update cohorts are
preserved below it. An existing reserved condition with a different expression,
an unrelated parameter using that name, or duplicate condition/parameter entries
causes preparation to fail. Review that scope before activation: it targets all
installations of this Firebase Android app, not one USB-connected device.

Use `-InputTemplatePath` with `-PrepareOnly` to review the complete merged template
against a saved export. The same merge is used during deployment, which always
fetches the current template. Without an input template, preparation emits only
the condition and parameter patch. Legacy mode requires a GitHub APK asset URL
whose exact release tag matches the installed version; `/releases/latest/`,
rollback aliases, and another version's URL are rejected.

The following is **preview only**. On September 8, 2026 the `v0.19.0+19` release
was not published, and its required backend migration/indexes were not deployed.
The URL validation checks syntax and version, not artifact availability, signing,
or package contents. Do not activate this policy until the intended users can
install the verified APK and its backend dependencies are ready.

```powershell
./tools/scripts/sync_release_remote_config.ps1 -PrepareOnly `
  -LatestVersion 0.19.0+19 -Platform android -IncludeLegacyAndroidPolicy `
  -DownloadUrl 'https://github.com/marolam/prox/releases/download/v0.19.0%2B19/app-release.apk' `
  -InputTemplatePath artifacts/r5_update_20260908/remote_config_before.json `
  -OutputPath artifacts/r5_update_20260908/android19-legacy-policy.preview.json
```

After deployment, an already-installed legacy app must fetch and activate the
condition before its gate can change. A USB installation proves an in-place
upgrade but does not verify delivery of a mandatory Remote Config policy. Build
18 also consults GitHub latest; preserve the existing latest release during an
Android-only migration and use the explicit minimum plus pinned install URL.
To roll back or advance this scoped policy later, update or remove its conditional
values as well as the platform defaults: a later default-only change will not
override this higher-priority condition.

The paired GitHub Actions workflow builds from one commit and a common defines
file, runs all Flutter tests and analysis, checks the exported iOS package version,
and records both artifact hashes. Backend CI must also pass before release: both
locked Node 22 dependency trees are audited, TypeScript is built, notifications
JavaScript is syntax-checked, and the real Firestore/Storage emulator tests run
against the isolated `demo-prox-audit` project using Java 21. It stages a new GitHub release as a draft until
every artifact upload succeeds. Tester/staging releases are prereleases and
cannot replace production latest. Rollback integrity is checked before and after
publication. Prepared policy JSON is attached as a build artifact; the workflow
does **not** activate a mandatory policy simply because an IPA uploaded to
TestFlight (processing and review may still be pending).

Run the policy script regression checks locally or in CI:

```powershell
./tools/scripts/test_update_release_policy.ps1
```

The paired workflow writes `artifacts/release/paired_defines.json` once and passes
that same file to `flutter build apk --release --dart-define-from-file=...` and
`flutter build ipa --release --dart-define-from-file=...`. For candidate
`0.19.0+19`, the common release settings are:

| Define | Paired value |
| --- | --- |
| `PROX_APP_VERSION`, `PROX_APP_VERSION_SHORT` | `0.19.0+19`, `0.19.0` |
| `PROX_RELEASE_CHANNEL` | One shared `tester`, `staging`, or `prod` channel |
| `PROX_TESTER_BUILD` | `true` for tester; otherwise `false` |
| `PROX_ENFORCE_MINIMUM_VERSION`, `PROX_MIN_REQUIRED_VERSION` | `true`, `0.19.0+19` |
| `PROX_PUBLIC_APK_URL`, `PROX_IOS_UPDATE_URL` | The real Android and iOS installation destinations |
| `PROX_ENABLE_BUSINESS_MODE`, `PROX_BUSINESS_MODE_FORCE_OFF`, `PROX_PRO_MODE_PREVIEW_ENABLED` | `false`, `true`, `false` for the general release |
| `PROX_TESTER_GUIDE_URL`, `PROX_TESTER_SUPPORT_URL` | The matching published guide/support pages |
| `PROX_EXTERNAL_CHECKOUT_SESSION_URL` | Shared configured backend endpoint, or empty when disabled |

Version defines are diagnostic fallbacks; native installed package metadata is
authoritative. Keep Flutter-generated plugin registration intact on both
platforms so that `package_info_plus` can read that metadata.

## Migration from existing installations

Read-only GitHub checks on September 8, 2026 found `v0.18.8+18` published
September 1 in both `marolam/prox-us` and `marolam/prox`; each latest release
contains only `app-release.apk`. This metadata does not establish that an
equivalent iOS build is distributed. `0.19.0+19` is a newer candidate version.

1. Build and test both native packages from the same candidate commit and
   common build defines. Keep the candidate draft/prerelease while either
   platform is unavailable to the intended users.
2. Validate the Android upgrade signed by the existing release key and the
   iOS installation through the actual App Store/TestFlight release. Complete
   Apple processing/review and confirm rollout availability.
3. Publish the paired production release only when both builds are installable.
   Older app code also reads GitHub latest as an update source; platform-scoped
   Remote Config alone cannot repair this behavior inside already-installed
   binaries. Avoid an Android-only latest promotion during this migration. If an
   Android-only migration is required before iOS is ready, use the explicit
   app-ID-scoped legacy policy described above after the Android artifact and
   backend are ready; keep shared defaults and GitHub latest unchanged.
4. Review `-PrepareOnly -Platform both` output with the installed candidate
   version and actual iOS install URL, then activate it after release signoff.
   The legacy shared keys are exactly `update_latest_version`,
   `update_minimum_required_version`, `update_minimum_required_enabled`,
   `update_force_latest_enabled`, `update_check_enabled`, and
   `update_download_url_ios`. Both platform overrides are written too.
5. Verify a known older Android and iOS installation are blocked, the new
   installations continue, a blocked offline restart remains blocked, and a
   subsequent successful refresh can apply an intentional policy rollback.

The privacy migration also depends on this order. Deploy the server-owned
`publicProfiles` publisher and backfill sanitized peer profiles before new clients
depend on it. Restrict root `users/{uid}` documents to their owner/admin after
the paired release and mandatory gates are available, because older clients read
peer profiles directly from those private documents. Review the backend migration
runbook before activating either the rules or the mandatory version policy.

Discovery now applies a geographic bounding box in Firestore before its bounded
candidate limit, then filters exact radius and freshness locally. Date-line
crossings use one OR query. Deploy the `presence` collection-group composite
index (`kind`, `latitude`, `longitude`, all ascending) and wait for it to become
ready before this client release. Presence writers must include numeric
`latitude` and `longitude` matching `geopoint`; the server compatibility mirror
is required for older installations during migration. Candidate work remains
bounded to 500 regional records, with up to four profile reads in flight; this
is a capped nearby list rather than exhaustive nearest-neighbor pagination.

Flutter CI uses the tested `3.41.1` SDK. All iOS compilation, signed IPA, paired
release and PR paths require analysis and regression tests to pass.

No release, Remote Config policy, or website association was published by this
audit. The Android preview was subsequently installed in place on R5 over USB;
see [the R5 verification report](r5_update_diagnosis_20260908.md). That local
installation does not validate the remote mandatory-update path.

A subsequent [R5 Nearby repair](r5_nearby_repair_20260908.md) installed the corrected
preview and deployed the specific Nearby index, projections, backfills, and
additive profile-read rules. Other build 19 backend services remain undeployed;
this does not authorize or activate a global version gate.

## Native setup and validation still required for distribution

Android uses API 36, a FragmentActivity and compatible themes for system
authentication. Both platforms explicitly disable Crashlytics collection by
default; the app's consent setting controls opt-in reporting. Android has the
Crashlytics Gradle plugin and iOS has a dSYM upload phase.

iOS declares the `prox` URL scheme, Push Notifications, and associated domains
for `prox-us.com` and `www.prox-us.com`. `app_links` owns URI handling on both
platforms. Distribution profiles must contain the push and associated-domain
entitlements; the paired workflow now checks this before archive. Firebase must
have an APNs key for the registered iOS app. The public domains must serve an
Apple App Site Association file matching the actual signing team and bundle ID;
Android requires corresponding Digital Asset Links. Repository configuration
alone cannot prove that those external associations are active.

The paired workflow requires the existing iOS signing/App Store Connect secrets
and these Android signing secrets: `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, and `ANDROID_STORE_PASSWORD`. Use the
same Android signing key as installed releases so upgrades preserve user data.
If publishing to a repository other than the workflow's repository, configure
`RELEASE_GITHUB_TOKEN` with release access to that destination; the default
workflow token is scoped to its own repository.
macOS/Xcode and real Android/iOS device checks are needed to validate signing,
push, biometric prompts, deep links, background behavior and actual upgrades.

The app can detect and require updates automatically. Installation remains under
the operating system and user's control. App Store/TestFlight and Google Play
background updates depend on store availability and device preferences. APK
installation needs Android user consent; iOS cannot silently replace its own
application bundle. Functional parity does not mean identical OS permission
dialogs or background execution guarantees.

Primary references checked for this audit:

- [Firebase Remote Config for Flutter](https://firebase.google.com/docs/remote-config/flutter/get-started)
- [Firebase Remote Config condition expressions](https://firebase.google.com/docs/remote-config/condition-reference)
- [Remote Config template fields and condition priority](https://firebase.google.com/docs/reference/remote-config/rest/v1/RemoteConfig)
- [Google Play in-app updates](https://developer.android.com/guide/playcore/in-app-updates)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Google Play target API requirement](https://developer.android.com/google/play/requirements/target-sdk)
- [Firebase Messaging setup for Flutter](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)
- [Flutter universal links](https://docs.flutter.dev/cookbook/navigation/set-up-universal-links)
- [Crashlytics Flutter setup](https://firebase.google.com/docs/crashlytics/flutter/get-started)
- [Crashlytics iOS symbol configuration](https://firebase.google.com/docs/crashlytics/ios/get-deobfuscated-reports)
- [Firestore range filters on multiple fields](https://firebase.google.com/docs/firestore/query-data/multiple-range-fields)
- [Flutter TextScaler accessibility contract](https://api.flutter.dev/flutter/painting/TextScaler-class.html)
