"""Resolve release inputs once for dispatch and tag pushes (no network writes)."""
import os
import re
import subprocess
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote, urlparse

VERSION = re.compile(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\+([1-9]\d*)")


def resolve(version, env):
    if not VERSION.fullmatch(version):
        raise ValueError("pubspec version must be x.y.z+build with a positive numeric build")
    channel = env.get("INPUT_RELEASE_CHANNEL") or "prod"
    ref = env.get("GITHUB_REF_NAME", "")
    if env.get("GITHUB_REF_TYPE") == "tag":
        channel = next((c for c in ("tester", "staging") if ref.endswith("-" + c)), "prod")
        if env.get("INPUT_RELEASE_CHANNEL") and env["INPUT_RELEASE_CHANNEL"] != channel:
            raise ValueError("Dispatch channel differs from the selected tag")
    elif env.get("GITHUB_EVENT_NAME") == "push":
        raise ValueError("Automatic releases require a version tag")
    if channel not in ("tester", "staging", "prod"):
        raise ValueError("Unknown release channel")
    tag = "v" + version + ("-" + channel if channel != "prod" else "")
    if env.get("GITHUB_REF_TYPE") == "tag" and ref != tag:
        raise ValueError(f"Tag must match pubspec.yaml exactly: {tag}")
    repo = env.get("RELEASE_REPO") or "marolam/prox"
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise ValueError("Invalid release repository")
    apk = (env.get("INPUT_STAGING_APK") or "app-release-staging.apk") if channel == "staging" else "app-release.apk"
    ipa = (env.get("INPUT_STAGING_IPA") or "app-release-staging.ipa") if channel == "staging" else "app-release.ipa"
    for name, extension in ((apk, "apk"), (ipa, "ipa")):
        if not re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9._-]*\." + extension, name):
            raise ValueError("Invalid release asset filename")
    apk_url = f"https://github.com/{repo}/releases/download/{quote(tag, safe='')}/{apk}"
    configured = env.get("INPUT_PUBLIC_APK_URL", "")
    if configured and configured != apk_url:
        raise ValueError("APK URL must be the exact asset URL for this release: " + apk_url)
    ios_url = env.get("IOS_UPDATE_URL", "")
    parsed = urlparse(ios_url)
    if ios_url and (parsed.scheme != "https" or parsed.hostname not in ("testflight.apple.com", "apps.apple.com")
            or parsed.username or parsed.password or parsed.port or parsed.path in ("", "/")):
        raise ValueError("Configure IOS_UPDATE_URL with the actual TestFlight/App Store install link")
    upload = env.get("UPLOAD_TO_TESTFLIGHT") or "true"
    export = env.get("EXPORT_METHOD") or "app-store"
    if upload not in ("true", "false") or export not in ("ad-hoc", "development", "app-store"):
        raise ValueError("Invalid iOS export/upload settings")
    if upload == "true" and export != "app-store":
        raise ValueError("TestFlight requires app-store export")
    notes = env.get("INPUT_NOTES_TEMPLATE") or "Prox {VERSION} ({CHANNEL}): Android APK and iOS IPA release."
    for key, value in {"VERSION": version, "SHORT_VERSION": version.split("+")[0],
                       "CHANNEL": channel, "REPO": repo,
                       "TIMESTAMP": datetime.now(timezone.utc).isoformat()}.items():
        notes = notes.replace("{" + key + "}", value)
    return dict(APP_VERSION=version, APP_VERSION_SHORT=version.split("+")[0], RELEASE_TAG=tag,
                RELEASE_CHANNEL=channel, RELEASE_REPO=repo, PUBLIC_APK_URL=apk_url,
                IOS_UPDATE_URL=ios_url, APK_ASSET_NAME=apk, IPA_ASSET_NAME=ipa,
                TESTER_BUILD=str(channel != "prod").lower(), UPLOAD_TO_TESTFLIGHT=upload,
                EXPORT_METHOD=export, BUILD_FLAVOR_IOS=env.get("INPUT_BUILD_FLAVOR_IOS") or "ios_device",
                EXTERNAL_CHECKOUT_SESSION_URL=env.get("INPUT_EXTERNAL_CHECKOUT_URL", ""),
                RELEASE_NOTES=notes)


def approved_branch(root, channel, env):
    """Tags have detached HEADs; enforce actual ancestry rather than renaming the ref."""
    if channel == "tester":
        return env.get("GITHUB_REF_NAME", "")
    if env.get("GITHUB_REF_TYPE") != "tag":
        branch = env.get("GITHUB_REF_NAME", "")
        if (channel == "prod" and branch == "main") or (channel == "staging" and branch.startswith("release/")):
            return branch
        raise ValueError("Production requires main; staging requires release/*")
    branches = subprocess.check_output(
        ["git", "-C", str(root), "for-each-ref", "--format=%(refname:short)", "refs/remotes/origin/"], text=True).splitlines()
    candidates = [b for b in branches if b == "origin/main"] if channel == "prod" else [b for b in branches if b.startswith("origin/release/")]
    for branch in candidates:
        result = subprocess.run(["git", "-C", str(root), "merge-base", "--is-ancestor", "HEAD", branch], check=False)
        if result.returncode == 0:
            return branch.removeprefix("origin/")
        if result.returncode != 1:
            raise ValueError("Unable to verify release ancestry")
    raise ValueError("Tagged commit is not on the approved release branch")


def main():
    root = Path(os.environ.get("PROJECT_DIR", "."))
    text = (root / "pubspec.yaml").read_text(encoding="utf-8-sig")
    version = re.search(r"^version:\s*(\S+)\s*$", text, re.MULTILINE)
    if not version:
        raise ValueError("Missing pubspec version")
    values = resolve(version[1], os.environ)
    values["RELEASE_BRANCH"] = approved_branch(root, values["RELEASE_CHANNEL"], os.environ)
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
        for key, value in values.items():
            delimiter = "release_" + uuid.uuid4().hex
            output.write(f"{key}<<{delimiter}\n{value}\n{delimiter}\n")
    print(f"Release {values['RELEASE_TAG']} from {values['RELEASE_BRANCH']} to {values['RELEASE_REPO']}")


if __name__ == "__main__":
    main()
