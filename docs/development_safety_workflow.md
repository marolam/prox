# Prox Development Safety Workflow

This project now treats the tester-approved `v1.0` APK as the safe rollback release.

## Safe Rollback Build

- Release: `v1.0`
- GitHub release asset: `app-release.apk`
- SHA-256: `ac7c2a184cbdf73bca9681a042efcbf92d0a414a7ca8948bb36df5b37d10c023`
- Local protected copy: `artifacts/rollback/v1.0/app-release.apk`
- Local canonical APK copy: `build/app/outputs/flutter-apk/app-release.apk`
- Rollback report: `artifacts/rollback/rollback_v1_0_20260620.md`

## What Each Tool Does

- Git tracks source code history. It tells us what changed and whether files are conflicted.
- Flutter builds and analyzes the app. It tells us whether Dart code can compile and whether app files agree with each other.
- GitHub releases hold APK files testers can download.
- PowerShell scripts tie those tools together so the same checks run every time.
- VS Code tasks are buttons for running the scripts without remembering the full command.

## Update Progression

1. Run `Safety: Pre-Update Gate` before code changes.
2. Make one focused change.
3. Run focused analyzer/tests for the changed area.
4. For Pro Mode work, run `R5 Pro Preview: Build + Install` first and verify the signed-in account is `marty.marola@hotmail.com`.
5. Install on the broader device set only after the R5 preview looks right.
6. Only publish after device checks pass.
7. Run `Safety: Verify Rollback Release` before and after any publish work.

## Safety Rules

- Do not overwrite `v1.0` unless intentionally replacing the rollback APK.
- Do not publish from a conflicted Git state.
- Do not treat a local APK as safe unless its hash matches the expected release hash.
- Prefer small changes with a check after each change.
- Keep Pro Mode preview account-gated to `marty.marola@hotmail.com`; do not broaden the allowlist without explicit approval.
- Keep rollback APK and report files under `artifacts/rollback/`.

## Scripts

- `tools/scripts/verify_safe_rollback_release.ps1`: confirms GitHub latest points to `v1.0` and that the APK hash/size match the known-good tester build.
- `tools/scripts/safe_update_gate.ps1`: checks for Git conflicts, can create a source snapshot, verifies the rollback release, and runs a focused Flutter analyzer.
- `tools/scripts/publish_github_release.ps1`: now refuses to overwrite `v1.0` with a different APK unless `-AllowOverwriteSafeRollback` is explicitly passed.
- `tools/scripts/build_r5_pro_preview_apk.ps1`: runs the safety gate, builds a Pro-preview APK with the Marty-only allowlist, and installs it only on R5 by default.

## Automation

- `.vscode/tasks.json` includes `Safety: Verify Rollback Release`, `Safety: Pre-Update Gate`, and `R5 Pro Preview: Build + Install`.
- `.github/copilot-instructions.md` tells future AI-assisted sessions to run the safety gates before risky app updates or release work.
- `.github/workflows/pr_safety_gates.yml` verifies the rollback release and runs the current project regression tests on pull requests.
- `.github/workflows/prod_release_guard.yml` verifies branch/flag safety and confirms the rollback release on main pushes.

## Plain Check Commands

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\verify_safe_rollback_release.ps1 -CheckLocalCanonicalApk
powershell -ExecutionPolicy Bypass -File .\tools\scripts\safe_update_gate.ps1 -CreateSnapshot -CheckLocalCanonicalApk
```
