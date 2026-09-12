# Automatic Android and TestFlight releases

The `Paired Android + iOS Release` workflow builds both native packages from a
version tag, uploads the IPA to App Store Connect/TestFlight, and publishes the
APK, IPA and `release-manifest.json` to the public `marolam/prox` GitHub release.
No local APK build, connected phone, or manual APK upload is required.

## Standing release authorization

As requested on September 12, 2026, publish a new paired Android/TestFlight
release whenever a significant change is complete and the candidate is stable.
Do not ask for release permission again for that routine cycle. Review the
intended source changes, run Flutter analysis and relevant tests, verify any
required backend deployment, and use a new build number on main. Keep generated
files and unrelated work out of the release commit. After CI verifies the signed
packages and published Android download, activate its Android update policy.
Report actual upload/publication results and any remaining device checks;
TestFlight upload alone does not prove Apple processing or tester availability.

## Tester Portal download

The live `https://www.prox-us.com/tester-portal.html` APK button uses
`https://github.com/marolam/prox/releases/latest/download/app-release.apk`.
The website link was published separately on September 12, 2026, replacing the
old pinned `v0.18.1` URL. Each newly published production release automatically
becomes the button's download; there is no website edit or second APK upload.
Drafts and tester/staging prereleases do not replace this download.

The paired workflow checks both the version-pinned download and this permanent
latest link against the built APK checksum before Android update-policy
activation. APK files are stored as GitHub Release assets; GitHub Pages serves
the portal HTML. Website linking does not activate Firebase in-app update policy.

PR #9 was merged into `main` on September 12, 2026 (commit `57d0ffd`), and the
paired release workflow is active. The release environments have no required
reviewers or wait timers. The private rollback token is configured and passed
the production release guard in GitHub Actions on September 12:
https://github.com/marolam/prox/actions/runs/34681739946 (attempt 2).
Matching version tags on main can now run the paired build/publication workflow
without manual approvals. No new release was published by this readiness check.

The implementation is in `.github/workflows/release_android_and_ios.yml`.
`release_parameters.py` resolves both tag and manual-dispatch inputs. The
publisher binds the remote tag to the exact checked-out commit and refuses to
replace a published release. `verify_release_artifacts.py` checks both native
package versions, the Android signing certificate and artifact checksums, then
verifies that the public APK download returns those exact bytes without a token.

## One-time repository setup

Commit the complete required application, native Android project, backend source,
tests, release scripts and workflows. The paired workflow and several dependencies
were untracked when this change was prepared. Adding only the workflow is not
sufficient. Retain the existing dependency lockfiles and native resources.

Configure these repository secrets on the repository running the workflow:

| Secret | Purpose |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 of the existing release keystore; do not generate a replacement key |
| `ANDROID_KEY_ALIAS` | Existing signing alias |
| `ANDROID_KEY_PASSWORD` | Existing key password |
| `ANDROID_STORE_PASSWORD` | Existing keystore password |
| `IOS_CERT_P12_BASE64`, `IOS_CERT_PASSWORD` | Apple distribution certificate |
| `IOS_PROVISION_PROFILE_BASE64`, `IOS_TEAM_ID` | App Store distribution profile/team for `com.prox-us.prox`, with push and associated domains |
| `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8_BASE64` | App Store Connect upload authentication |
| `ROLLBACK_GITHUB_TOKEN` | Read access to the protected `v1.0` release in private `marolam/prox-us` |
| `RELEASE_GITHUB_TOKEN` | Only needed when publishing to another repository; requires contents write access there |
| `FIREBASE_SERVICE_ACCOUNT` | Google service-account JSON for Remote Config deployment, only if automatic Android policy activation is enabled |

The ordinary workflow token can publish in its own repository but cannot read
the private rollback repository. Rollback verification uses the rollback token,
falling back to the release token and then the workflow token. Signing secrets
are not printed or uploaded as build artifacts.

Configure repository variables:

| Variable | Value |
| --- | --- |
| `IOS_UPDATE_URL` | Optional real TestFlight join link or App Store app link; invite-only TestFlight uploads work without one |
| `ANDROID_SIGNING_CERT_SHA256` | SHA-256 certificate digest from a known installed/published APK, as printed by `apksigner verify --print-certs`; this is the certificate digest, not the APK checksum |
| `RELEASE_REPO` | Optional; defaults to `marolam/prox` |
| `AUTO_PUBLISH_ANDROID_POLICY` | Set to `true` after backend readiness and rollout scope are verified; otherwise policy is prepared only |
| `UPDATE_LEGACY_ANDROID_POLICY` | Set to `true` if deployed clients need shared update keys or the reserved legacy Android condition already exists |

The workflow selects `paired-release-gate-prod`, `paired-release-gate-staging`,
or `paired-release-gate-tester`. Configure their allowed deployment branches/tags
and secrets as needed. Environment rules must permit the corresponding version
tags. Required reviewers, if configured, intentionally pause deployment;
unattended releases require environment settings that allow them.

On September 10, the four Android signing secrets and certificate digest were
configured in `marolam/prox` after the local key was verified against the actual
published build 19 APK. The existing iOS upload secrets were already present,
and all three release environments were created. The private rollback token
was configured on September 12 and its repository access verified from CI.
The protected private `v1.0` is not interchangeable with public `v1.0`: their
APK checksums differ.

A read-only App Store Connect lookup confirmed app `6798915421`, bundle
`com.prox-us.prox`, with internal and external `Prox Testers` groups. The external
group's public link is disabled. Uploads support this invite-only setup; omitting
`IOS_UPDATE_URL` skips iOS policy preparation and keeps the app's existing portal
fallback. No tester group, public access setting, or App Store build was changed.
To repeat this inspection using the existing CI-held API key:

```powershell
gh workflow run ios_signed_device_ipa.yml --ref release/paired-automation-20260910 -f inspect_testflight=true
```

This mode performs only App Store Connect GET requests and skips all builds and
uploads. The workflow is now available with `--ref main`.

PR and production branch guards use the same private rollback credential. The
production branch guard allows a committed version bump to precede its tag;
matching the uploaded artifact to the version is checked during publication.

## Release a version

The next candidate is `0.19.0+21`; `0.19.0+19` is already publicly released,
and iOS `0.19.0+20` has already been uploaded to TestFlight. Build 21's meetup,
Party, and safety changes are still local and need their backend rollout before
publication. Do not tag the older build 20 on main for another TestFlight upload.
Increase the numeric build number for every new Android/iOS upload, across all
channels. Never reuse a TestFlight build number to promote a tester build by
rebuilding it as production.

1. Set `pubspec.yaml` to `x.y.z+build` and commit the reviewed source.
2. Push the source commit to the approved branch.
3. Push a matching version tag. For example, after committing build 21 on `main`:

   ```powershell
   git tag -a 'v0.19.0+21' -m 'Prox 0.19.0+21'
   git push origin 'v0.19.0+21'
   ```

The workflow rejects tags whose version differs from `pubspec.yaml`.
Production tags must point to commits contained in `origin/main`. A tag such as
`v0.19.0+21-staging` requires containment in an `origin/release/*` branch.
`v0.19.0+22-tester` selects tester mode. Each example assumes the corresponding
build number in pubspec. Tester and staging GitHub releases are prereleases and
do not advance production latest or activate a global update policy.

Manual dispatch remains available. It defaults to App Store export and TestFlight
upload. For ad-hoc installation, select `ad-hoc` and explicitly disable TestFlight
upload. On a selected tag, the dispatch channel must match the tag suffix.

If the release destination differs from the source repository, tag runs require
the same tag and commit in the destination as well. Manual dispatch may create a
tag only after verifying the built commit exists in that repository. This
prevents a release from silently tagging the destination's unrelated default
branch.

## Update activation and Apple availability

Firebase Remote Config is the update authority for the new app code; there is no
`version.json` feed. `web/tester-guide-release.json` is separate website metadata
and is not the updater's source of truth. `release-manifest.json` records the
published package version, commit, filenames, hashes and signing certificate.

The workflow prepares Android policy JSON and, when an install URL is configured,
separate iOS policy JSON as Actions artifacts. Production Android policy is activated automatically only when
`AUTO_PUBLISH_ANDROID_POLICY=true`, after the public APK checksum is verified.
This uses a version-pinned URL, never a potentially stale `latest` redirect.
It does not redeploy the application backend or its database indexes: complete
any required migration before enabling an update requirement.

If the legacy Android condition exists, default-only updates are rejected instead
of silently remaining masked by the older conditional value. Set
`UPDATE_LEGACY_ANDROID_POLICY=true` to advance that condition while preserving
iOS defaults and unrelated configuration.

An IPA upload is not proof that testers can install it. Apple processing,
test-group assignment and external beta review remain App Store Connect concerns.
The workflow never automatically advances the iOS minimum. After the exact build
is available to all intended iOS users, activate its prepared policy using:

```powershell
./tools/scripts/sync_release_remote_config.ps1 -Platform ios `
  -LatestVersion '0.19.0+20' -IosDownloadUrl 'https://testflight.apple.com/join/REAL_CODE'
```

Replace the example URL and version with the verified release. Legacy iOS clients
that read shared keys require the migration process in
[update_policy_and_platform_release.md](update_policy_and_platform_release.md).
Those old clients may also infer updates from GitHub latest; do not use a
production latest promotion as an Android-only migration while they remain in
service. Use tester/staging prereleases and a reviewed pinned Android migration
policy until both platform populations can safely follow production latest.

If policy activation fails after publication, the release remains published and
is never clobbered by a retry. Resolve Firebase configuration and rerun the policy
script for the verified published version; do not rebuild/reupload that version
to TestFlight. A failed draft before publication may be resumed at the same
commit; Apple may already have accepted its build, so disable TestFlight upload
on a manual retry only after confirming the matching upload succeeded.

## Local shipping and working-tree hygiene

`ship_it_2.ps1` remains a local Android build/install convenience. It uses channel
suffixes and prerelease publication for tester/staging builds, skips production
website/referral/policy changes for those channels, and never changes iOS policy.
`-SkipBuildInstall` with publication requires `-SkipVersionBump`. The publisher
still refuses a previously published version and requires the commit to exist in
the destination repository. Push reviewed source before local publication.
Normal preflight verifies the protected remote rollback. Comparing the current
local build output with the rollback checksum is opt-in through
`ship_it_preflight.ps1 -CheckLocalRollbackApk`, since ordinary builds intentionally
replace the local APK output.

`.gitignore` excludes Android `.cxx/`, compiled `functions/lib/`, accidental nested
`functions/functions/`, Python caches and the two captured phone logs. It retains
Android Gradle files, manifests, Kotlin, resources and Firebase configuration.
The two previously tracked compiled Functions files (`index.js` and
`index.js.map`) have been removed from Git tracking and remain on disk. Their
removal is committed with the ignore-rule change; Firebase's existing
TypeScript predeploy build recreates them. No application source or generated
output was deleted from disk by this change.

Validation commands (no publication):

```powershell
python -m unittest discover -s tools/scripts/tests -p 'test_release*.py'
node --test tools/scripts/tests/test_testflight_inspection.mjs
powershell -NoProfile -File tools/scripts/test_update_release_policy.ps1
flutter test test/login_update_prompt_test.dart test/update_policy_test.dart test/update_enforcement_gate_test.dart
```

The release tests run the real PowerShell publisher against a temporary Git
repository and a fake GitHub CLI. They exercise tag provenance, published-release
immutability, API failures, build ordering, draft asset upload order, package
identity/signing checks and anonymous download checksums without publishing.
