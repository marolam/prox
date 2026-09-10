"""Verify release packages and the anonymous Android download before activation."""
import argparse
import hashlib
import json
import os
import plistlib
import re
import subprocess
import urllib.request
import zipfile
from pathlib import Path
from urllib.parse import quote


def validate_android(badging, signing, version, expected_certificate):
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.MULTILINE)
    if not package or package[1] != "com.prox.app" or f"{package[3]}+{package[2]}" != version:
        raise ValueError("APK package/version differs from the intended release")
    expected = expected_certificate.lower().replace(":", "").strip()
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError("Set ANDROID_SIGNING_CERT_SHA256 to the existing installed release certificate digest")
    certificates = re.findall(r"^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]+)$", signing, re.MULTILINE)
    if len(certificates) != 1 or certificates[0].lower() != expected:
        raise ValueError("APK is not signed with the expected installed-app release certificate")
    return expected


def validate_ios(info, version):
    actual = f"{info.get('CFBundleShortVersionString')}+{info.get('CFBundleVersion')}"
    if actual != version or info.get("CFBundleIdentifier") != "com.prox-us.prox":
        raise ValueError("IPA bundle ID/version differs from the intended release")


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_published(manifest, url):
    expected_url = (f"https://github.com/{manifest['repository']}/releases/download/"
                    f"{quote(manifest['tag'], safe='')}/{manifest['android']['asset']}")
    if url != expected_url:
        raise ValueError("Published APK URL does not match the verified release manifest")
    # Deliberately anonymous: a CI token must not mask a private download URL.
    request = urllib.request.Request(url, headers={"User-Agent": "Prox-release-verification"})
    checksum = hashlib.sha256()
    size = 0
    with urllib.request.urlopen(request, timeout=60) as response:
        if response.status != 200:
            raise ValueError("APK download did not return HTTP 200")
        while chunk := response.read(1024 * 1024):
            checksum.update(chunk)
            size += len(chunk)
    if size != manifest["android"]["size"] or checksum.hexdigest() != manifest["android"]["sha256"]:
        raise ValueError("Public APK bytes do not match the verified, signed build")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--published", action="store_true")
    args = parser.parse_args()
    manifest_path = Path("artifacts/release/release-manifest.json")
    if args.published:
        verify_published(json.loads(manifest_path.read_text()), os.environ["PUBLIC_APK_URL"])
        print("Anonymous download matches the verified Android package and checksum.")
        return
    version = os.environ["APP_VERSION"]
    apk = Path("build/app/outputs/flutter-apk") / os.environ["APK_ASSET_NAME"]
    ipa = Path("build/ios/ipa") / os.environ["IPA_ASSET_NAME"]
    sdk = Path(os.environ.get("ANDROID_HOME") or os.environ["ANDROID_SDK_ROOT"])
    build_tools = sdk / "build-tools/36.0.0"
    badging = subprocess.check_output([str(build_tools / "aapt"), "dump", "badging", str(apk)], text=True)
    signing = subprocess.check_output([str(build_tools / "apksigner"), "verify", "--verbose", "--print-certs", str(apk)], text=True)
    certificate = validate_android(badging, signing, version, os.environ.get("ANDROID_SIGNING_CERT_SHA256", ""))
    with zipfile.ZipFile(ipa) as archive:
        info_names = [n for n in archive.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info.plist", n)]
        if len(info_names) != 1:
            raise ValueError("IPA must contain exactly one application Info.plist")
        validate_ios(plistlib.loads(archive.read(info_names[0])), version)
    manifest = dict(version=version, commit=os.environ["GITHUB_SHA"], channel=os.environ["RELEASE_CHANNEL"],
                    tag=os.environ["RELEASE_TAG"], repository=os.environ["RELEASE_REPO"],
                    ios_update_url=os.environ["IOS_UPDATE_URL"])
    for key, path in (("android", apk), ("ios", ipa)):
        manifest[key] = dict(asset=path.name, sha256=digest(path), size=path.stat().st_size)
    manifest["android"]["signing_certificate_sha256"] = certificate
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Verified Android/iOS package identities, version {version}, Android signer and both checksums.")


if __name__ == "__main__":
    main()
