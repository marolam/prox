import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from release_parameters import approved_branch, resolve
from verify_release_artifacts import validate_android, validate_ios, verify_published


class ReleaseParametersTests(unittest.TestCase):
    def setUp(self):
        self.env = dict(GITHUB_REF_TYPE="tag", GITHUB_REF_NAME="v0.19.0+20", GITHUB_EVENT_NAME="push",
                        IOS_UPDATE_URL="https://testflight.apple.com/join/testers")

    def test_tag_defaults_build_upload_and_public_url(self):
        result = resolve("0.19.0+20", self.env)
        self.assertEqual(result["RELEASE_CHANNEL"], "prod")
        self.assertEqual(result["UPLOAD_TO_TESTFLIGHT"], "true")
        self.assertEqual(result["EXPORT_METHOD"], "app-store")
        self.assertEqual(result["TESTER_BUILD"], "false")
        self.assertEqual(result["PUBLIC_APK_URL"], "https://github.com/marolam/prox/releases/download/v0.19.0%2B20/app-release.apk")
        self.assertIn("0.19.0+20", result["RELEASE_NOTES"])

    def test_prerelease_tags_select_channel_and_asset(self):
        for channel in ("tester", "staging"):
            result = resolve("0.19.0+20", dict(self.env, GITHUB_REF_NAME=f"v0.19.0+20-{channel}"))
            self.assertEqual(result["RELEASE_CHANNEL"], channel)
            self.assertEqual(result["TESTER_BUILD"], "true")
            self.assertIn(f"%2B20-{channel}/", result["PUBLIC_APK_URL"])

    def test_dispatch_can_disable_testflight_for_ad_hoc(self):
        result = resolve("0.19.0+20", dict(self.env, GITHUB_REF_TYPE="branch", GITHUB_REF_NAME="main",
                         GITHUB_EVENT_NAME="workflow_dispatch", EXPORT_METHOD="ad-hoc", UPLOAD_TO_TESTFLIGHT="false"))
        self.assertEqual(result["EXPORT_METHOD"], "ad-hoc")
        self.assertEqual(result["UPLOAD_TO_TESTFLIGHT"], "false")

    def test_reject_mismatch_missing_link_and_invalid_settings(self):
        for override in [dict(GITHUB_REF_NAME="v0.19.0+19"), dict(GITHUB_REF_TYPE="branch"),
                         dict(INPUT_RELEASE_CHANNEL="tester"),
                         dict(IOS_UPDATE_URL="https://testflight.apple.com.evil.test/join/testers"),
                         dict(IOS_UPDATE_URL="https://testflight.apple.com/"),
                         dict(EXPORT_METHOD="ad-hoc"), dict(UPLOAD_TO_TESTFLIGHT="yes"),
                         dict(INPUT_PUBLIC_APK_URL="https://github.com/marolam/prox/releases/latest/download/app-release.apk")]:
            with self.subTest(override=override), self.assertRaises(ValueError):
                resolve("0.19.0+20", dict(self.env, **override))

    def test_invite_only_testflight_does_not_require_public_join_link(self):
        result = resolve("0.19.0+20", dict(self.env, IOS_UPDATE_URL=""))
        self.assertEqual(result["IOS_UPDATE_URL"], "")
        self.assertEqual(result["UPLOAD_TO_TESTFLIGHT"], "true")

    def test_tag_ancestry_uses_commit_containment(self):
        with patch("release_parameters.subprocess.check_output", return_value="origin/main\norigin/release/next\n"), \
             patch("release_parameters.subprocess.run", return_value=subprocess.CompletedProcess([], 1)):
            with self.assertRaisesRegex(ValueError, "not on the approved"):
                approved_branch(".", "prod", self.env)
        with patch("release_parameters.subprocess.check_output", return_value="origin/main\n"), \
             patch("release_parameters.subprocess.run", return_value=subprocess.CompletedProcess([], 0)):
            self.assertEqual(approved_branch(".", "prod", self.env), "main")


class ReleaseArtifactTests(unittest.TestCase):
    def test_portal_latest_download_must_match_production_build(self):
        import hashlib
        from verify_release_artifacts import verify_latest
        data = b"current published APK"
        manifest = dict(repository="marolam/prox", channel="prod", android=dict(
            asset="app-release.apk", size=len(data), sha256=hashlib.sha256(data).hexdigest()))
        response = io.BytesIO(data)
        response.status = 200
        with patch("verify_release_artifacts.urllib.request.urlopen", return_value=response) as request:
            verify_latest(manifest)
            self.assertEqual(request.call_args.args[0].full_url,
                             "https://github.com/marolam/prox/releases/latest/download/app-release.apk")
            self.assertNotIn("Authorization", request.call_args.args[0].headers)
        response = io.BytesIO(b"previous APK")
        response.status = 200
        with patch("verify_release_artifacts.urllib.request.urlopen", return_value=response), self.assertRaises(ValueError):
            verify_latest(manifest)
        with self.assertRaises(ValueError):
            verify_latest(dict(manifest, channel="tester"))

    def test_android_identity_version_and_signer(self):
        badging = "package: name='com.prox.app' versionCode='20' versionName='0.19.0'"
        signing = "Signer #1 certificate SHA-256 digest: " + "a" * 64
        self.assertEqual(validate_android(badging, signing, "0.19.0+20", "a" * 64), "a" * 64)
        for actual, signature, expected in [(badging.replace("20", "19"), signing, "a" * 64),
                                            (badging.replace("com.prox.app", "other.app"), signing, "a" * 64),
                                            (badging, signing, "b" * 64), (badging, signing, "")]:
            with self.assertRaises(ValueError):
                validate_android(actual, signature, "0.19.0+20", expected)

    def test_ios_version_and_identity(self):
        info = dict(CFBundleShortVersionString="0.19.0", CFBundleVersion="20", CFBundleIdentifier="com.prox-us.prox")
        validate_ios(info, "0.19.0+20")
        with self.assertRaises(ValueError):
            validate_ios(dict(info, CFBundleVersion="19"), "0.19.0+20")

    def test_anonymous_download_rejects_wrong_bytes(self):
        import hashlib
        data = b"verified APK bytes"
        manifest = dict(repository="marolam/prox", tag="v0.19.0+20", android=dict(
            asset="app-release.apk", size=len(data), sha256=hashlib.sha256(data).hexdigest()))
        url = "https://github.com/marolam/prox/releases/download/v0.19.0%2B20/app-release.apk"
        response = io.BytesIO(data)
        response.status = 200
        with patch("verify_release_artifacts.urllib.request.urlopen", return_value=response) as request:
            verify_published(manifest, url)
            self.assertNotIn("Authorization", request.call_args.args[0].headers)
        response = io.BytesIO(b"incorrect release")
        response.status = 200
        with patch("verify_release_artifacts.urllib.request.urlopen", return_value=response), self.assertRaises(ValueError):
            verify_published(manifest, url)
        with self.assertRaises(ValueError):
            verify_published(manifest, url.replace("%2B20", "%2B19"))


@unittest.skipUnless(shutil.which("pwsh") or shutil.which("powershell"), "PowerShell required")
class ReleasePublisherTests(unittest.TestCase):
    """Run the real publisher against an isolated repository and a fake GitHub CLI."""
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        (self.root / "pubspec.yaml").write_text("version: 0.19.0+20\n")
        subprocess.run(["git", "-C", str(self.root), "add", "pubspec.yaml"], check=True)
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                        "commit", "-qm", "fixture"], check=True)
        self.sha = subprocess.check_output(["git", "-C", str(self.root), "rev-parse", "HEAD"], text=True).strip()
        script_dir = self.root / "tools/scripts"
        script_dir.mkdir(parents=True)
        self.script = script_dir / "publish_github_release.ps1"
        shutil.copyfile(SCRIPTS / self.script.name, self.script)
        (script_dir / "verify_safe_rollback_release.ps1").write_text("exit 0\n")
        self.apk = self.root / "app-release.apk"
        self.apk.write_bytes(b"fixture apk")
        self.log = self.root / "calls.jsonl"
        self.responses = self.root / "responses.json"
        self.api = {
            "repos/test/releases/releases/tags/v0.19.0%2B20": None,
            "repos/test/releases/git/ref/tags/v0.19.0%2B20": dict(object=dict(type="commit", sha=self.sha)),
            "repos/test/releases/releases/latest": dict(tag_name="v0.19.0+19"),
        }
        mock = self.root / "mock_gh.py"
        mock.write_text('''import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['MOCK_GH_LOG'], 'a') as log: log.write(json.dumps(args) + '\\n')
if args[0] == 'api':
    responses = json.loads(Path(os.environ['MOCK_GH_RESPONSES']).read_text())
    if args[1] not in responses:
        print('unexpected endpoint', file=sys.stderr); sys.exit(2)
    value = responses[args[1]]
    if value is None:
        print('gh: Not Found (HTTP 404)', file=sys.stderr); sys.exit(1)
    if value == 'forbidden':
        print('gh: Forbidden (HTTP 403)', file=sys.stderr); sys.exit(1)
    print(json.dumps(value))
elif args[:2] == ['release', 'view']: print('https://example.invalid/release')
''')
        executable = self.root / ("gh.cmd" if os.name == "nt" else "gh")
        if os.name == "nt":
            executable.write_text(f'@echo off\n"{sys.executable}" "{mock}" %*\nexit /b %errorlevel%\n')
        else:
            executable.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{mock}" "$@"\n')
            executable.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ["PATH"],
                        GH_TOKEN="fixture", MOCK_GH_LOG=str(self.log), MOCK_GH_RESPONSES=str(self.responses))

    def invoke(self, *args):
        self.responses.write_text(json.dumps(self.api))
        return subprocess.run([shutil.which("pwsh") or shutil.which("powershell"), "-NoProfile", "-ExecutionPolicy", "Bypass",
                               "-File", str(self.script), "-RepoPath", str(self.root), "-Repo", "test/releases",
                               "-Tag", "v0.19.0+20", "-TargetCommit", self.sha, *args],
                              env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_preflight_does_not_publish(self):
        result = self.invoke("-ValidateOnly", "-RequireExistingTag")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue(all(c[0] == "api" for c in self.calls()))

    def test_published_release_is_never_clobbered(self):
        self.api["repos/test/releases/releases/tags/v0.19.0%2B20"] = dict(draft=False)
        result = self.invoke("-ApkPath", str(self.apk))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already published", result.stdout)
        self.assertTrue(all(c[0] == "api" for c in self.calls()))

    def test_mismatched_remote_tag_is_rejected(self):
        self.api["repos/test/releases/git/ref/tags/v0.19.0%2B20"]["object"]["sha"] = "0" * 40
        result = self.invoke("-ValidateOnly")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not point", result.stdout)

    def test_annotated_tag_resolves_to_built_commit(self):
        self.api["repos/test/releases/git/ref/tags/v0.19.0%2B20"] = dict(object=dict(type="tag", sha="a" * 40))
        self.api["repos/test/releases/git/tags/" + "a" * 40] = dict(object=dict(type="commit", sha=self.sha))
        result = self.invoke("-ValidateOnly", "-RequireExistingTag")
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_missing_remote_tag_is_rejected_for_tag_runs(self):
        self.api["repos/test/releases/git/ref/tags/v0.19.0%2B20"] = None
        result = self.invoke("-ValidateOnly", "-RequireExistingTag")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("before publishing", result.stdout)

    def test_manual_release_verifies_target_commit_exists_in_destination(self):
        self.api["repos/test/releases/git/ref/tags/v0.19.0%2B20"] = None
        self.api["repos/test/releases/commits/" + self.sha] = dict(sha=self.sha)
        result = self.invoke("-ValidateOnly")
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_api_permission_error_is_not_treated_as_absent_release(self):
        self.api["repos/test/releases/releases/tags/v0.19.0%2B20"] = "forbidden"
        result = self.invoke("-ApkPath", str(self.apk))
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(all(c[0] == "api" for c in self.calls()))

    def test_older_build_cannot_replace_latest(self):
        self.api["repos/test/releases/releases/latest"] = dict(tag_name="v0.19.0+21")
        result = self.invoke("-ValidateOnly")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("build number must increase", result.stdout)

    def test_new_release_targets_commit_and_uploads_metadata_before_promotion(self):
        metadata = self.root / "release-manifest.json"
        metadata.write_text('{}')
        result = self.invoke("-ApkPath", str(self.apk), "-AdditionalAssets", str(metadata), "-RequireExistingTag")
        self.assertEqual(result.returncode, 0, result.stdout)
        calls = self.calls()
        create = next(c for c in calls if c[:2] == ["release", "create"])
        self.assertEqual(create[create.index("--target") + 1], self.sha)
        self.assertIn("--verify-tag", create)
        upload_index = next(i for i, c in enumerate(calls) if c[:2] == ["release", "upload"] and str(metadata) in c)
        edit_index = next(i for i, c in enumerate(calls) if c[:2] == ["release", "edit"])
        self.assertLess(upload_index, edit_index)

    def test_existing_draft_can_resume_but_stays_bound_to_commit(self):
        self.api["repos/test/releases/releases/tags/v0.19.0%2B20"] = dict(draft=True, target_commitish=self.sha)
        result = self.invoke("-ApkPath", str(self.apk), "-RequireExistingTag")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(any(c[:2] == ["release", "create"] for c in self.calls()))
        self.assertTrue(any(c[:2] == ["release", "edit"] for c in self.calls()))


@unittest.skipUnless(shutil.which("powershell"), "Windows local ship script requires powershell")
class LocalShipTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        script_dir = self.root / "tools/scripts"
        script_dir.mkdir(parents=True)
        (self.root / "pubspec.yaml").write_text("version: 0.19.0+20\n")
        shutil.copyfile(SCRIPTS / "ship_it_2.ps1", script_dir / "ship_it_2.ps1")
        stubs = {
            "ship_it_preflight.ps1": "throw 'Unexpected preflight'",
            "release_build_install_publish.ps1": "Param($DeviceIds,$Repo,$PublicApkUrl,$ReleaseChannel,[switch]$SkipBuildInstall,[switch]$AllowPartialDeviceDeploy)\nexit 0",
            "publish_github_release.ps1": "Param($Repo,$Tag,$Title,$Notes,[switch]$Prerelease,[switch]$SetLatest=$true)\n@{tag=$Tag; prerelease=$Prerelease.IsPresent; latest=$SetLatest.IsPresent} | ConvertTo-Json | Set-Content mirror.json\nexit 0",
            "sync_release_download_targets.ps1": "throw 'Unexpected website sync'",
            "sync_release_remote_config.ps1": "Param($ProjectId,$LatestVersion,$Platform,$DownloadUrl,$IosDownloadUrl,$UpdatePollMinutes)\n@{platform=$Platform; version=$LatestVersion; url=$DownloadUrl} | ConvertTo-Json | Set-Content policy.json\nexit 0",
            "check_referral_qr_release_link.ps1": "Param($PublicApkUrl,[switch]$AllowNonLatestGithubPath)\nexit 0",
        }
        for filename, text in stubs.items():
            (script_dir / filename).write_text(text)

    def invoke(self, channel, *args):
        return subprocess.run([shutil.which("powershell"), "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                               str(self.root / "tools/scripts/ship_it_2.ps1"), "-ReleaseChannel", channel,
                               "-SkipBuildInstall", "-SkipPreflightChecks", "-SkipVersionBump", *args],
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def test_tester_and_staging_do_not_advance_latest_or_policy(self):
        for channel in ("tester", "staging"):
            with self.subTest(channel=channel):
                result = self.invoke(channel)
                self.assertEqual(result.returncode, 0, result.stdout)
                mirror = json.loads((self.root / "mirror.json").read_text(encoding="utf-8-sig"))
                self.assertEqual(mirror, dict(tag=f"v0.19.0+20-{channel}", prerelease=True, latest=False))
                self.assertFalse((self.root / "policy.json").exists())

    def test_apple_url_does_not_advance_ios_from_android_ship(self):
        result = self.invoke("prod", "-SkipDownloadTargetSync", "-IosUpdateUrl", "https://testflight.apple.com/join/testers")
        self.assertEqual(result.returncode, 0, result.stdout)
        policy = json.loads((self.root / "policy.json").read_text(encoding="utf-8-sig"))
        self.assertEqual(policy["platform"], "android")
        self.assertEqual(policy["version"], "0.19.0+20")
        self.assertIn("v0.19.0%2B20/app-release.apk", policy["url"])


if __name__ == "__main__":
    unittest.main()
