# Prox growth rollout rollback baseline

The October 5, 2026 baseline preserves the working app before growth work. Source
restoration was actually performed in a new directory and checked against every
captured file. A separate cloud drill imported the database export into an
isolated named database and verified every document against the exact snapshot.
The connected Android device also completed an authenticated upgrade to
`0.20.0+27`, downgrade to `0.19.0+26`, and re-upgrade to `0.20.0+27` without
uninstalling. This verifies the captured debug-signed device path; production
database restoration and production-signed device downgrade were not performed.

## Protected locations

- Primary: `artifacts/rollback/20261005_pre_growth_094316/`
- Independent mirror: `C:/Users/marty/Documents/ProxRollback/20261005_pre_growth_094316/`
- Restored drill: `C:/Users/marty/Documents/prox_restore_drill_20261005_094316/`

Both local backup directories are on the same physical C drive. The complete
frozen baseline also has a verified private off-device copy:

`gs://prox-42bef-rollback-us-central1/pre-growth-20261005_094316/full-local-baseline-20261005T103804767Z/`

Its private `cloud-upload-manifest.json` records **265 files, 1,633,955,195
bytes** (~1.52 GiB), including the exact dirty source archive, full Git history,
index/patches, local signing/configuration, both build-26 APKs, phone baseline
APK/private-data archive/debug key, later screenshots/UI evidence, deployed
function source/IAM/configuration, and complete Remote Config template. Every
uploaded object's generation, size, server CRC32C and server MD5 matched local
checksums; SHA-256 is recorded in the manifest and object metadata. A subsequent
full download into
`C:/Users/marty/Documents/prox_cloud_backup_download_drill2_20261005/` verified
the **actual SHA-256 bytes of all 265 objects**, including full history and
private phone data, against the uploaded manifest. The downloaded source
archive/Git components, all 90 backend files, and all 38 cloud backup/restore
evidence files then passed the independent recovery verifier. The cloud
manifest itself was also downloaded and checked by SHA-256. See
`full-download-verification.json` and `offdevice-recovery-verification.json`.

Private upload evidence is preserved in `cloud-offdevice-verified/` under both
baseline directories. The cloud manifest's SHA-256 is
`c08babf222ecb04cfd34cc2ba5598341fa17ce64182162c7305ba9c8411a4e37`.
The bucket readback confirms uniform access, enforced public access prevention,
no public IAM bindings, object versioning, and an **unlocked 30-day retention
policy**. The retention policy was never irreversibly locked; an administrator
can remove it, so this is protection against accidental deletion rather than an
absolute guarantee against deliberate administrative removal. Versioned
objects consume storage until removed. These protections also cover the
existing database export and copied app Storage objects in this private bucket.

To recover the off-device baseline, use an authenticated Firebase CLI account
with access to the private bucket, then download into a new outside-workspace
directory. This helper verifies every actual downloaded file by SHA-256 and
never extracts phone data or restores production:

```powershell
node tools/scripts/download_growth_rollback.cjs `
  gs://prox-42bef-rollback-us-central1/pre-growth-20261005_094316/full-local-baseline-20261005T103804767Z/cloud-upload-manifest.json `
  C:/Users/marty/Documents/prox_cloud_recovery_NEW `
  --manifest-sha256 c08babf222ecb04cfd34cc2ba5598341fa17ce64182162c7305ba9c8411a4e37

python tools/scripts/restore_growth_rollback.py `
  C:/Users/marty/Documents/prox_cloud_recovery_NEW `
  --destination C:/Users/marty/Documents/prox_source_recovery_NEW
```

These private backups include ignored native signing configuration and local
environment inputs. Do not commit, attach to public releases, or upload their
contents to public artifact storage. The application code, native projects,
backend source/configuration, untracked source, original index, staged/unstaged
patches and Git history were captured. Generated dependencies and build caches
can be recreated and are not required for source restoration.

The verified drill restored **734 files**, preserved **3 deleted tracked files**
as absent, and recreated branch `release/meetup-safety-21` at
`42361b569260718b37a8ce481894566e8bd5ab25`. The restored Git index matched the
original checksum. See `restore-drill.json` and `baseline-verification.json` in
the protected baseline directory.

## Exact Android artifacts

Before installing an older baseline binary after testing background matching,
turn background matching off in the candidate and verify its native collector
has stopped and its server preference/presence is disabled. Clear only the
dedicated native collector preferences (`prox_background_matching` on Android;
`prox.bg.enabled`, `prox.bg.uid`, `prox.bg.deviceId`, `prox.bg.mode` on iOS) if
needed. Also disable the account's separate Flutter background opt-in preference
through its settings control; clearing native preferences alone does not prevent
an older Dart implementation from restoring that opt-in on launch. Do not clear
the full app/auth preferences or uninstall as a shortcut. A debuggable Android
installation can inspect its dedicated preference file using authenticated ADB
`run-as`; a production signed installation requires its in-app control or an
appropriate compatible maintenance build. The new availability gate cannot
retroactively change the exact baseline binary, so do this preparation before
downgrade. The preserved original phone data archive is recovery evidence, not
a command to overwrite current app data automatically.

| Artifact | Actual installed version/build | SHA-256 |
| --- | --- | --- |
| Published APK, baseline `app-release.apk` | `0.19.0`, build `26` | `5440bedf65adbd3a067aa004ea30e824f252d4ad53076b5613597630391d9a31` |
| Earlier USB APK, baseline `local-usb-build26.apk` | `0.19.0`, build `26` | `656a1dbd80e6567ece610052d1dec5ff341fba505f2c23433185331a819af691` |
| Historic protected `artifacts/rollback/v1.0/app-release.apk` | `0.18.0`, build `1` | `ac7c2a184cbdf73bca9681a042efcbf92d0a414a7ca8948bb36df5b37d10c023` |

The production and USB files have the same version/build but different content.
They must remain separate. All three packages identify `com.prox.app` and their
signatures verify against certificate SHA-256
`d643a5d8992dff485607e4f152de7aa3db9eb4c7fd3c9619f9d520a302dadad3`.
The [published production release](https://github.com/marolam/prox/releases/tag/v0.19.0%2B26)
contains the APK only. An equivalent iOS distribution was not verified.

## Verify and restore source

Run from this repository, or copy the restore script to a trusted local location.
Use a new destination outside the active workspace. The script refuses existing
destinations and never overwrites the current project.

```powershell
python tools/scripts/restore_growth_rollback.py `
  artifacts/rollback/20261005_pre_growth_094316 `
  --backend-baseline artifacts/rollback/20261005_pre_growth_094316/backend-complete

python tools/scripts/restore_growth_rollback.py `
  C:/Users/marty/Documents/ProxRollback/20261005_pre_growth_094316 `
  --destination C:/Users/marty/Documents/prox_recovery_NEW
```

Verification checks companion hashes, ZIP membership, each source file hash and
size, deleted paths, the captured Git HEAD/branch, and the original index. Backend
verification also checks the downloaded source ZIP CRCs. After restoration,
open the new directory, restore dependencies using the preserved lockfiles, and
run the relevant Flutter/backend checks. Changing the original workspace is a
separate action; the recovery script has no destructive in-place mode.

Future checkpoints can be captured with
`tools/scripts/create_growth_rollback.py NEW_BACKUP --mirror NEW_MIRROR`.
Pass `--apk PATH_TO_EXISTING_VERIFIED_APK` to preserve a specific exact binary.
Capture while source edits are paused. The older `safe_update_gate.ps1` snapshot
omits native projects and several backend inputs, so it is insufficient by itself
for this rollout.

## Backend baseline and actual limits

`backend-complete/` was captured through read-only APIs in project `prox-42bef`.
It contains **39 exact deployed function source archives** (10 generation 1,
29 generation 2), their runtime/deployment metadata and all 39 function IAM
policies; active Firestore/Storage rules; Remote Config version **19**, including
conditional values; indexes/field overrides; and database/backup metadata.
All **90** captured backend source/configuration files have verified hashes.
The capture did not retrieve Secret Manager secret payloads.

The observed Android legacy condition currently requires/recommends
`0.19.0+23` with a pinned build 23 APK link. Several default values still say
build 19. Defaults alone do not undo a conditional policy. iOS policy still
references `0.18.0+10` and its configured TestFlight URL is a placeholder. Preserve
the entire template and review each platform/condition before policy activation
or restoration.

The original read-only configuration capture found PITR disabled and no scheduled
or retained backups. Those original files remain immutable. The user's authorized
protective work subsequently enabled PITR and created the verified cloud backups
below. New growth data should use additive isolated collections and preserve
existing user, matching, meetup, billing, and points documents.

## Verified database and Storage protection

- Private dedicated bucket: `gs://prox-42bef-rollback-us-central1`, in
  `US-CENTRAL1`, with uniform bucket access and enforced public access prevention.
  Its IAM policy has no public principals.
- Firestore PITR: enabled and independently read back with `604800s` retention.
- Exact database checkpoint: **October 5, 2026, 6:03 a.m. EDT**
  (`2026-10-05T10:03:00Z`). The completed snapshot export is
  `gs://prox-42bef-rollback-us-central1/pre-growth-20261005T100455016/firestore`.
  It contains **1,409 documents**, across **11 export objects** totaling
  **675,293 bytes**; object generations and CRC32C checksums were captured.
- Existing app Storage: **57 objects**, totaling **22,465,528 bytes**, copied
  server side into `pre-growth-20261005T100130528/storage/` in the private bucket.
  Every copy used the captured source generation and matched its original size,
  CRC32C and MD5 checksum. No original object changed during capture. Full original
  object metadata remains in the private `storage-before.json`; a recovery must
  restore that metadata together with the payload when required.
- Cloud restore drill: the snapshot was imported into the new isolated named
  database `prox-rollback-drill-20261005-muv37e6o`. Deny-all client rules and
  anonymous HTTP 403 were verified before import. **All 1,409 restored document
  field fingerprints matched production reads at the exact checkpoint timestamp.**
  Production default rules and database identity were unchanged. Only the owned
  drill database was deleted afterward, and authenticated list readback verified
  that cleanup.

Evidence is in `cloud-data-complete/`, `cloud-data-snapshot-verified/`, and
`cloud-restore-drill-verified/`, beside the source archive and in the independent
mirror. A transient CLI transport error dropped the drill database deletion
response; cleanup was verified through a separate authenticated database-list
request and that distinction is recorded in the report. The managed full export
was also preserved; the snapshot export above is the checkpoint used for the
verified restore.

The baseline database/index metric was approximately **5.7 MiB**, and app Storage
approximately **21.4 MiB**. Protection used same-region server-side copies and
bounded size checks. PITR and backup storage incur usage-based charges;
[Google's pricing documentation](https://cloud.google.com/firestore/pricing)
describes those charges. PITR retains historical versions as time passes, so
enabling it does not immediately create seven days of history.
[PITR documentation](https://firebase.google.com/docs/firestore/use-pitr)

Use `protect_growth_cloud_data.cjs NEW_PRIVATE_REPORT_DIRECTORY` for read-only
size inspection, adding `--execute` for a new authorized protective checkpoint.
The script never imports into production or deletes application data. It refuses
unexpected regions, public buckets and unexpectedly large copies. The isolated
drill command is:

```powershell
node tools/scripts/verify_growth_cloud_restore.cjs `
  artifacts/rollback/20261005_pre_growth_094316/cloud-data-snapshot-verified/cloud-data-manifest.json `
  NEW_PRIVATE_DRILL_REPORT_DIRECTORY --execute
```

The export and isolated restore establish an actual data recovery path. A
production import still needs a recovery plan that preserves valid later user
activity and handles external side effects such as payment-provider charges or
deleted authentication accounts. Firestore import overwrites matching document
IDs and retains documents absent from the export; it does not automatically make
the entire database identical to an earlier snapshot.
[Firestore export/import behavior](https://firebase.google.com/docs/firestore/manage-data/export-import)

For an authorized backend recovery: first disable new growth execution using its
server configuration; preserve current evidence/data; restore the captured rules
and complete Remote Config template if they changed; and redeploy only affected
functions from their captured source archives with the captured runtime, trigger,
IAM and secret-version configuration. Existing function names/generation and
triggers must be retained. Do not use a blanket functions deployment that deletes
functions absent from a recovery folder. Database restoration is a separate,
reviewed operation that must preserve valid activity after the checkpoint.

## Verified device drill and native recovery limits

The original connected-device baseline is preserved privately under
`device-baseline/`: `base.apk` identifies `com.prox.app`, version `0.19.0`, build
`26`; `private-app-data.tar` contains 75 archive entries and 100,327,936 bytes;
and `debug.keystore` preserves that installation's signing identity. All three
files were rechecked against their manifest's size and SHA-256. The original
APK, private data archive, and key are included in the verified private
off-device backup. The debug signer differs from the public release signer;
installing the production-signed APK over this debug installation is not a
compatible update.

`device-baseline/native-rollback-drill.json` records this actual device sequence:

| Step | Verified installed version/build | Authenticated app screen |
| --- | --- | --- |
| Upgrade | `0.20.0+27` | Present |
| Rollback | `0.19.0+26` | Present |
| Re-upgrade | `0.20.0+27` | Present |

Private screenshots and UI captures accompany those records. The authenticated
Business HQ screen remained available through the sequence, demonstrating that
this tested downgrade retained sign-in and visible account state without
uninstalling. This is not a byte-for-byte comparison of all app data, an import
of the saved private archive, or proof that a production-signed installation can
downgrade. The rollback/re-upgrade record and four accompanying image/UI files
were created after the frozen 265-file upload. They were independently mirrored
with matching SHA-256 and uploaded as a separate immutable five-file addition
(859,506 bytes) under
`gs://prox-42bef-rollback-us-central1/pre-growth-20261005_094316/full-local-baseline-20261005T112734150Z/`.
The original cloud manifest remains unchanged. Additional private evidence is
`artifacts/rollback/native-drill-offdevice-proof/cloud-upload-manifest.json`.

Installing an archived APK with a lower version code can be rejected by Android,
including when an installer retries with `-d`. Uninstalling clears private local
app data and cannot be considered a data-preserving rollback. The successful
debug-signed drill does not remove those production installer restrictions.

For a production rollback that retains upgrade eligibility, rebuild the captured
baseline behavior with the original signing key and a build number above the
latest installed release; validate it before distributing it as a recovery
release. iOS likewise needs a valid signed, newly numbered build through the
actual TestFlight/App Store distribution. Keep mandatory update policy compatible
with the recovery build and old clients. The saved APKs establish exact binary
integrity; they do not prove that every device can downgrade without data loss.
