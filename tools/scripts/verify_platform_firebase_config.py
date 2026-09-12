"""Offline identity check for all Android/iOS build variants. No credentials printed."""
import json
import plistlib
import re
from pathlib import Path

root = Path(__file__).resolve().parents[2]
gradle_properties = (root / "android/gradle.properties").read_text(encoding="utf-8-sig")
assert not re.search(r"^\s*org\.gradle\.java\.home\s*=", gradle_properties, re.M), (
    "Do not commit a machine-specific Gradle Java home; select the JDK in the environment."
)
source = (root / "lib/firebase_options.dart").read_text(encoding="utf-8-sig")


def options(platform):
    match = re.search(r"FirebaseOptions " + platform + r" = FirebaseOptions\((.*?)\n  \);", source, re.S)
    assert match, f"Missing {platform} Firebase options"
    return dict(re.findall(r'(\w+): "([^"]+)"', match[1]))


android = options("android")
ios = options("ios")
assert android["projectId"] == ios["projectId"], "Platform Firebase projects differ"
assert android["messagingSenderId"] == ios["messagingSenderId"], "Platform messaging projects differ"
gradle = (root / "android/app/build.gradle").read_text()
package = re.search(r'applicationId "([^"]+)"', gradle)[1]
for relative in ("android/app/google-services.json", "android/app/src/debug/google-services.json", "android/app/src/release/google-services.json"):
    config = json.loads((root / relative).read_bytes())
    assert config["project_info"]["project_id"] == android["projectId"], f"Project mismatch: {relative}"
    client = next((client for client in config["client"] if client["client_info"]["android_client_info"]["package_name"] == package), None)
    assert client, f"No registered client for {package}: {relative}"
    assert client["client_info"]["mobilesdk_app_id"] == android["appId"], f"App ID mismatch: {relative}"
    assert any(key["current_key"] == android["apiKey"] for key in client["api_key"]), f"API key mismatch: {relative}"

config = plistlib.loads((root / "ios/Runner/GoogleService-Info.plist").read_bytes())
for native, dart in (("PROJECT_ID", "projectId"), ("GOOGLE_APP_ID", "appId"), ("BUNDLE_ID", "iosBundleId"), ("API_KEY", "apiKey")):
    assert config[native] == ios[dart], f"iOS {native} mismatch"
project = (root / "ios/Runner.xcodeproj/project.pbxproj").read_text()
bundle_ids = re.findall(r'PRODUCT_BUNDLE_IDENTIFIER = "([^"]+)";', project)
assert all(value == ios["iosBundleId"] or value == ios["iosBundleId"] + ".RunnerTests" for value in bundle_ids), "Xcode bundle ID mismatch"
print("Firebase identity verified: Android debug/profile/release and iOS use the same intended project and matching app registrations.")
