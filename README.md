# prox_app_new

Flutter app + Firebase backend for Prox.

## Creator Announcements + Broadcasts

HQ Announcements are now Firestore-backed and can be published from the in-app Creator Panel (admin claim required).

- Firestore path: `dashboard/announcements/items/{announcementId}`
- Dashboard reads active announcements from this path
- Optional push blast on publish when `broadcast=true`

Audience options:

- `all`
- `business_only`
- `self` (creator-only test blast)

Cloud Functions triggers:

- `onDashboardAnnouncementCreate`
- `onBusinessSubscriptionCongratsParty`

## Support Tickets -> Google Sheets Export

Support ticket export trigger:

- `onSupportTicketCreatedExportSheets`

Trigger source:

- `support_tickets/{ticketId}` on create

Environment variable required for webhook delivery:

- `SUPPORT_SHEETS_WEBHOOK_URL`

If not configured, export is skipped safely and logged.

## External Payment Scaffold (Card Checkout)

Cloud Functions endpoints:

- `createExternalCheckoutSession` (POST, authenticated user)
- `verifyExternalCheckoutCallback` (POST, provider callback)
- `onSquareWebhookBridge` (POST, Square webhook adapter)

Purpose:

- Prepare provider-agnostic external checkout sessions for Business SKUs.
- Apply entitlements and invoice records after verified callback status `paid`.

Environment variables:

- `EXTERNAL_PAYMENT_CHECKOUT_BASE_URL` (optional; defaults to `https://example.com/checkout`)
- `PROX_PAYMENT_CALLBACK_SECRET` (required for callback verification)
- `PROX_CHECKOUT_SUCCESS_URL` (required; checkout success redirect URL)
- `PROX_CHECKOUT_CANCEL_URL` (required; checkout cancel redirect URL)
- `PROX_TAX_POLICY` (required; e.g. `manual_none_until_defined`, `flat_rate`, `state_rules`)
- `PROX_BIZ_MONTHLY_DEV_PRICE_ENABLED` (optional; when `true`, monthly SKU uses `$0.01` for dev/testing)
- `SQUARE_ACCESS_TOKEN` (required for real Square checkout session creation)
- `SQUARE_LOCATION_ID` (required for real Square checkout session creation)
- `SQUARE_WEBHOOK_SIGNATURE_KEY` (required for Square webhook signature validation)
- `SQUARE_WEBHOOK_ENDPOINT_URL` (recommended; exact URL Square signs against)
- `PROX_EXTERNAL_CHECKOUT_SESSION_URL` (required in app build dart-define for real in-app card checkout)

Callback status mapping for monthly subscriptions:

- `paid` -> activate Business subscription and set 30-day renewal window
- `canceled` / `cancelled` / `unpaid` / `past_due` / `payment_failed` / `failed` -> immediate downgrade
- any other status -> callback accepted with no entitlement mutation

Square webhook bridge behavior:

- Verifies `x-square-hmacsha256-signature`
- Maps events to internal statuses and applies entitlement/invoice updates
- Resolves checkout sessions via `order.reference_id` (`prox_session:<sessionId>`) or provider session id

Current app behavior:

- Business paywall includes a beta card-checkout scaffold action that creates an external checkout intent.
- Final processor session handoff is intentionally staged for provider integration hardening.

Env/config gate script:

- `tools/scripts/check_external_payment_env.ps1`

Run manually:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\check_external_payment_env.ps1 -RequireSquareSecrets
```

Callback smoke script:

- `tools/scripts/check_external_payment_callback.ps1`

Run manually:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\check_external_payment_callback.ps1 -Url "https://<region>-<project>.cloudfunctions.net/verifyExternalCheckoutCallback" -Uid "<uid>" -SessionId "<sessionId>" -CallbackSecret "<secret>"
```

## Real In-App Payment Test (Square)

Preflight helper (recommended):

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\prep_real_payment_test.ps1 -RunHttpPreflight
```

This runs env validation, verifies basic function endpoint contracts, and prints the exact app build command and webhook URL to configure in Square.

One-command readiness chain (preflight + build + strict signoff):

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\run_real_payment_readiness.ps1 -ExternalCheckoutSessionUrl "https://<region>-<project>.cloudfunctions.net/createExternalCheckoutSession" -PublicApkUrl "https://example.com/public/app-release.apk" -RestrictedApkUrl "https://example.com/tester/app-release.apk" -PreviousApkUrl "https://example.com/public/previous-app-release.apk"
```

1. Set backend env vars (including Square secrets and checkout success/cancel/tax policy).
2. Deploy functions so `createExternalCheckoutSession` and `onSquareWebhookBridge` are live.
3. In Square dashboard, set webhook URL to your deployed `onSquareWebhookBridge` endpoint and subscribe to these events:
	- `payment.created`
	- `invoice.paid`
	- `subscription.created`
	- `subscription.updated`
	- `subscription.canceled`
	- `refund.created`
4. Build app with dart-define:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\build_dev_release_apk.ps1 -ExternalCheckoutSessionUrl "https://<region>-<project>.cloudfunctions.net/createExternalCheckoutSession"
```

5. In app, open Business paywall and tap monthly card checkout.
6. Complete payment in Square-hosted checkout page.
7. Confirm entitlement update under `users/{uid}/billing/entitlements` and invoice entry under `users/{uid}/billing/invoices/items`.

## Backend Smoke Checks

Admin observability endpoints:

- `getActiveModeSweepHealth` (GET, admin-only)
- `runActiveModeSweepNow` (POST, admin-only)

PowerShell script:

- `tools/scripts/check_admin_observability_endpoints.ps1`

Run manually:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\check_admin_observability_endpoints.ps1
```

Strict mode (fails if no admin token is available):

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\check_admin_observability_endpoints.ps1 -FailIfNoAuthToken
```

Admin token environment variable names accepted by the script:

- `PROX_ADMIN_BEARER_TOKEN`
- `ADMIN_BEARER_TOKEN`

VS Code tasks:

- `Backend Smoke: Admin Observability Endpoints`
- `Backend Smoke (Strict Auth): Admin Observability Endpoints`

## Build Tasks

Common tasks are available in `.vscode/tasks.json`, including:

- `Flutter Build APK`
- `Flutter Build iOS`
- `Flutter Build Release APK`

## APK Download Endpoint Gate

Use this script before sharing tester/public download links to confirm access mode and APK headers.

Script:

- `tools/scripts/check_apk_download_endpoint.ps1`

Examples:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\check_apk_download_endpoint.ps1 -Url "https://your.domain/downloads/app-release.apk" -ExpectedAccess public
```

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\check_apk_download_endpoint.ps1 -Url "https://your.domain/tester/app-release.apk" -ExpectedAccess restricted
```

VS Code tasks:

- `Release Gate: APK Endpoint (Public)`
- `Release Gate: APK Endpoint (Restricted)`

## One-Command Release Signoff

Use the release signoff runner to execute build + endpoint checks and auto-generate a one-page report with APK metadata.

Script:

- `tools/scripts/run_release_signoff.ps1`

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\run_release_signoff.ps1 -PublicApkUrl "https://your.domain/downloads/app-release.apk" -RestrictedApkUrl "https://your.domain/tester/app-release.apk" -PreviousApkUrl "https://your.domain/downloads/app-release-prev.apk" -SmokeResultsPath ".\logs\smoke\latest_smoke_results.txt" -FatalLogGate PASS
```

Outputs:

- `logs/release_reports/release_one_page_<timestamp>.md`

VS Code task:

- `Release Signoff: Build + Endpoint + Report`

## Virtual Test Environment (Pre-Tester)

Use the Android emulator sandbox before handing builds to human testers.

One-command setup (boots emulator, builds tester APK, installs, launches):

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\setup_virtual_test_env.ps1 -AvdName prox_api35 -BuildMode debug
```

What it does:

- Starts and waits for the selected AVD (`prox_api35` by default)
- Builds APK with tester defines:
	- `PROX_TESTER=true`
	- `PROX_TESTER_BUILD=true`
	- `BUILD_FLAVOR=virtual_env`
- Installs and launches app on emulator

Optional hardening pass before build:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\setup_virtual_test_env.ps1 -AvdName prox_api35 -BuildMode debug -RunStabilityGate -RunFlutterAnalyze
```

VS Code task:

- `Android Virtual Test Env (Tester Build)`

## Emulator Smoke Automation

Use this script to run a quick emulator gate that prepares the AVD, installs a tester build, relaunches app, and scans logcat for fatal/regression patterns.

Script:

- `tools/scripts/run_emulator_smoke.ps1`

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\run_emulator_smoke.ps1 -AvdName prox_api35 -BuildMode debug
```

What it validates:

- Emulator boot and app install/launch
- App process is running after cold relaunch
- No `FATAL EXCEPTION`, `AndroidRuntime`, `NoSuchMethodError`, `Unhandled Exception`, or `permission-denied` patterns in current logcat

Output:

- `logs/verification/emulator_smoke_<timestamp>.logcat.txt`

VS Code task:

- `Android Emulator Smoke: Boot + Install + Crash Scan`

## Dev Release Rebuild + Run (`dr`)

Use `dr` for a dev/tester-flavored release rebuild and install/launch on connected devices.

Wrapper command (repo root):

```cmd
dr
```

This runs:

- `tools/scripts/build_dev_release_apk.ps1`

What it does:

- Builds release APK with tester/dev defines:
	- `PROX_TESTER=true`
	- `PROX_TESTER_BUILD=true`
	- `BUILD_FLAVOR=dev_release`
- Reuses `tools/scripts/build_release_apk.ps1 -SkipBuild` to install and launch on target devices.

Examples:

```cmd
dr -DeviceIds R5CT51EDX0H
```

```cmd
dr -DeviceIds R5CT51EDX0H ZY22L74Z8N -CleanInstall
```

## Dev User Simulator (Internal Testing)

You now have a dev-only in-app simulator panel plus a Firestore seed/motion script.

In-app panel:

- Open `Dev Menu` -> `Dev User Simulator`
- Spawn presets: 1, 5, 10, 50 simulated nearby users
- Tune radius, keyword overlap, online ratio, mutual-match chance, and motion interval
- Start/stop motion and clear simulation state

Script files:

- `tools/scripts/dev_user_simulator.js`
- `tools/scripts/run_dev_user_simulator.ps1`

PowerShell example (one-shot seed + optional match/chat docs):

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\run_dev_user_simulator.ps1 --sourceUid <YOUR_UID> --count 10 --radiusMiles 2.0 --keywordOverlap 0.6 --onlineRate 0.85 --mutualMatchChance 0.35 --withMatches --withChats
```

PowerShell example (continuous motion updates every 4s):

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\run_dev_user_simulator.ps1 --sourceUid <YOUR_UID> --count 10 --radiusMiles 2.0 --keywordOverlap 0.6 --onlineRate 0.85 --mutualMatchChance 0.35 --withMatches --withChats --motion --intervalSec 4
```

Firestore docs written by the script:

- `users/{uid}`
- `users/{uid}/presence/current`
- `profiles/{uid}`
- optional `matches/{pairId}` + `chats/{pairId}` (+ optional chat message docs)
