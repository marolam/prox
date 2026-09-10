# iOS Device Testing

This repo now has a Flutter iOS host project under `ios/` for the Prox app bundle ID `com.prox-us.prox`.

## Current Firebase iOS App

- Firebase project: `prox-42bef`
- Firebase iOS app: `Prox iOS`
- Firebase app ID: `1:12575732319:ios:295d3725a038e4dc5561ea`
- Bundle ID: `com.prox-us.prox`
- Config files: `ios/Runner/GoogleService-Info.plist`, `ios/firebase_app_id_file.json`, `lib/firebase_options.dart`

## First Mac Setup

Run these from a Mac with Xcode, CocoaPods, Flutter, and the iPhone trusted by macOS:

```sh
flutter doctor -v
flutter pub get
cd ios
pod install
cd ..
flutter devices
```

Open `ios/Runner.xcworkspace` in Xcode and set the Runner target Signing & Capabilities team. Keep the bundle identifier as `com.prox-us.prox`.

For the first device run, use a tester/dev flavor so it stays separate from release publishing:

```sh
flutter run -d <iphone-device-id> \
  --dart-define=PROX_TESTER=true \
  --dart-define=PROX_TESTER_BUILD=true \
  --dart-define=BUILD_FLAVOR=ios_device
```

## App Check Notes

Debug iOS builds use `AppleDebugProvider`. If Firebase calls fail with App Check, copy the debug token from the Xcode run logs and allowlist it in Firebase App Check for the iOS app.

Release iOS builds use `AppleDeviceCheckProvider`. Before any TestFlight or public iOS release, configure Firebase App Check DeviceCheck for the Apple developer team and verify Auth, Firestore, Storage, Remote Config, Messaging, location, camera/photo upload, and notifications on a real device.

## Windows Limitation

Windows can validate Dart, plist XML, and Firebase config, but it cannot build, sign, or install the iOS app. The actual iPhone build must be done on macOS/Xcode.

## No-Mac Path From PC (Cloud Build)

You can still run iOS compile checks from Windows using GitHub Actions macOS runners.

Workflow file: `.github/workflows/ios_cloud_compile.yml`

What it does:

- Runs on `macos-14`
- Runs `flutter pub get` + `flutter analyze`
- Compiles iOS with `flutter build ios --release --no-codesign`
- Uploads `Runner-no-codesign.zip` as a build artifact

How to run from PC:

1. Push your branch to GitHub.
2. Open GitHub -> Actions -> `iOS Cloud Compile`.
3. Click `Run workflow`.
4. Download artifact `Runner-no-codesign` from the run summary.

Important:

- This cloud workflow proves iOS compile health but does not produce an installable iPhone app.
- For iPhone install/testing, you still need signing + provisioning done on macOS (local Mac or cloud Mac service).

## No-Mac Path From PC (Signed iPhone IPA)

You can build a signed IPA in GitHub Actions with this workflow:

- `.github/workflows/ios_signed_device_ipa.yml`

This workflow can produce an installable IPA for a real iPhone when signing secrets are configured.

Required repository secrets:

- `IOS_CERT_P12_BASE64`: Base64 of your Apple signing certificate `.p12`
- `IOS_CERT_PASSWORD`: Password used when exporting that `.p12`
- `IOS_PROVISION_PROFILE_BASE64`: Base64 of your `.mobileprovision`
- `IOS_TEAM_ID`: Apple Developer Team ID

Optional repository secrets for TestFlight upload:

- `APP_STORE_CONNECT_API_KEY_ID`: App Store Connect API key ID
- `APP_STORE_CONNECT_ISSUER_ID`: App Store Connect API issuer ID
- `APP_STORE_CONNECT_API_KEY_P8_BASE64`: Base64 of the App Store Connect API key `.p8`

How to run from PC:

1. Push your branch to GitHub.
2. Open GitHub -> Actions -> `iOS Signed Device IPA`.
3. Click `Run workflow` and keep `export_method` as `ad-hoc` for direct tester installs.
4. Download artifact `Runner-signed-ipa` from the run summary.

TestFlight path from PC (no Mac required):

1. Ensure your provisioning profile is App Store distribution compatible for bundle ID `com.prox-us.prox`.
2. Open GitHub -> Actions -> `iOS Signed Device IPA`.
3. Click `Run workflow` with:
  - `export_method=app-store`
  - `upload_to_testflight=true`
4. Wait for completion, then check App Store Connect -> TestFlight for processing status.

Fast CLI helper in this repo:

- `tools/scripts/run_ios_cloud_compile_and_download.ps1`

Example for the signed workflow:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\scripts\run_ios_cloud_compile_and_download.ps1 `
  -Branch ios-cloud-compile-20260730 `
  -Workflow ios_signed_device_ipa.yml `
  -ArtifactName Runner-signed-ipa
```

Notes:

- The provisioning profile must match bundle ID `com.prox-us.prox` and include your iPhone UDID for ad-hoc installs.
- If you prefer TestFlight, use an App Store distribution profile and upload the IPA to App Store Connect.