#!/usr/bin/env python3
"""Capture dirty and untracked Prox source, Git history/index and local build inputs.

The resulting archive includes private local signing/runtime configuration. It
must stay in a private backup location, never a public release or Git commit.
"""

import argparse
import datetime
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

from restore_growth_rollback import digest, verify_backup


GENERATED = {".git", "artifacts", "build", "node_modules", ".dart_tool", ".gradle", ".cxx", "Pods", ".symlinks", "__pycache__"}


def git(workspace, *args):
    return subprocess.run(["git", "-C", str(workspace), *args], check=True, capture_output=True).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path, help="New private backup directory")
    parser.add_argument("--workspace", type=Path, default=Path.cwd())
    parser.add_argument("--mirror", type=Path, help="Optional second NEW backup directory on another location")
    parser.add_argument("--apk", type=Path, help="Exact existing Android binary to preserve (no rebuild or download)")
    args = parser.parse_args()
    workspace, destination = args.workspace.resolve(), args.destination.resolve()
    if destination.exists() or (args.mirror and args.mirror.resolve().exists()):
        raise ValueError("Backup and mirror destinations must not already exist")
    if git(workspace, "ls-files", "-u").strip():
        raise ValueError("Resolve Git merge conflicts before capturing a release baseline")
    tracked = {name.decode("utf-8") for name in git(workspace, "ls-files", "-z").split(b"\0") if name}
    untracked = {name.decode("utf-8") for name in git(workspace, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0") if name}
    candidates = set(tracked)
    candidates.update(name for name in untracked if not (set(Path(name).parts) & GENERATED))
    # Include ignored build inputs without including generated dependency trees.
    for root_name in ("android", "ios", "functions", "functions_notifications"):
        root = workspace / root_name
        if not root.exists():
            continue
        import os
        for current, directories, names in os.walk(root):
            directories[:] = [name for name in directories if name not in GENERATED]
            for name in names:
                path = Path(current) / name
                if name.startswith(".env") or path.suffix.lower() in {".jks", ".keystore", ".p12", ".mobileprovision"} or name in {"key.properties", "local.properties", "google-services.json", "GoogleService-Info.plist"}:
                    candidates.add(path.relative_to(workspace).as_posix())
    for name in (".env", ".env.local", ".firebaserc"):
        if (workspace / name).is_file():
            candidates.add(name)
    destination.mkdir(parents=True)
    head = git(workspace, "rev-parse", "HEAD").decode().strip()
    manifest = {"createdUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "workspace": str(workspace),
                "head": head, "branch": git(workspace, "branch", "--show-current").decode().strip(), "files": {},
                "missingTracked": sorted(name for name in tracked if not (workspace / name).exists())}
    with zipfile.ZipFile(destination / "workspace.zip", "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(candidates):
            source = workspace / name
            if not source.is_file():
                continue
            if source.is_symlink():
                raise ValueError("Source symlinks need a dedicated platform-aware backup")
            content = source.read_bytes()
            manifest["files"][name] = {"size": len(content), "sha256": hashlib.sha256(content).hexdigest()}
            archive.writestr(name, content)
    git(workspace, "bundle", "create", str(destination / "history.bundle"), "--all", "HEAD")
    index = Path(git(workspace, "rev-parse", "--git-path", "index").decode().strip())
    if not index.is_absolute():
        index = workspace / index
    shutil.copyfile(index, destination / "git-index")
    (destination / "unstaged.patch").write_bytes(git(workspace, "diff", "--binary"))
    (destination / "staged.patch").write_bytes(git(workspace, "diff", "--cached", "--binary"))
    (destination / "git-status.txt").write_bytes(git(workspace, "status", "--short"))
    for name in ("workspace.zip", "history.bundle", "git-index", "unstaged.patch", "staged.patch", "git-status.txt"):
        manifest[name + "Sha256"] = digest(destination / name)
    if args.apk:
        shutil.copyfile(args.apk.resolve(), destination / "app-release.apk")
        manifest["app-release.apkSha256"] = digest(destination / "app-release.apk")
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    verify_backup(destination)
    if args.mirror:
        shutil.copytree(destination, args.mirror.resolve())
        verify_backup(args.mirror.resolve())
    print(json.dumps({"verified": True, "backup": str(destination), "files": len(manifest["files"]), "head": head,
                      "mirrorVerified": bool(args.mirror)}))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("Rollback capture failed: " + str(error), file=sys.stderr)
        sys.exit(1)
