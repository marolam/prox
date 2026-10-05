#!/usr/bin/env python3
"""Verify a Prox rollback archive, or restore it into a NEW directory.

This intentionally has no in-place mode. The archive may contain local signing
configuration: keep the backup and restored directory private.
"""

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path, PurePosixPath


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def safe_relative(value):
    path = PurePosixPath(value.replace("\\", "/"))
    if path.is_absolute() or ".." in path.parts or not path.parts or ":" in value:
        raise ValueError("Unsafe relative path in backup manifest or archive")
    if path.parts[0].casefold() == ".git":
        raise ValueError("Workspace archive must not contain a .git directory")
    return path


def run_git(*args, cwd=None):
    result = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError("Git rollback operation failed: " + result.stderr.strip())
    return result.stdout.strip()


def verify_backup(backup):
    manifest = json.loads((backup / "manifest.json").read_text(encoding="utf-8"))
    for field, expected in manifest.items():
        if field.endswith("Sha256"):
            name = field[:-len("Sha256")].rstrip(".")
            if digest(backup / name) != expected:
                raise ValueError("Backup component checksum mismatch: " + name)
    expected_files = manifest["files"]
    normalized = [str(safe_relative(name)) for name in expected_files]
    if len({name.casefold() for name in normalized}) != len(normalized):
        raise ValueError("Duplicate or conflicting paths in backup manifest")
    with zipfile.ZipFile(backup / "workspace.zip") as archive:
        members = {}
        for member in archive.infolist():
            if member.is_dir():
                continue
            name = str(safe_relative(member.filename))
            if name in members or (member.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError("Duplicate or symbolic-link archive entry")
            members[name] = member
        if set(members) != set(expected_files):
            raise ValueError("Archive and manifest do not contain the same files")
        for name, metadata in expected_files.items():
            content = archive.read(members[name])
            if len(content) != metadata["size"] or hashlib.sha256(content).hexdigest() != metadata["sha256"]:
                raise ValueError("Archived file checksum mismatch: " + name)
    for name in manifest.get("missingTracked", []):
        safe_relative(name)
        if name in expected_files:
            raise ValueError("A deleted tracked file is present in the archive")
    heads = run_git("bundle", "list-heads", str(backup / "history.bundle"))
    if not any(line.split()[0] == manifest["head"] for line in heads.splitlines()):
        raise ValueError("Captured HEAD is absent from the Git history bundle")
    return manifest


def verify_restore(destination, manifest):
    for name, metadata in manifest["files"].items():
        path = destination.joinpath(*safe_relative(name).parts)
        if not path.is_file() or path.stat().st_size != metadata["size"] or digest(path) != metadata["sha256"]:
            raise ValueError("Restored file checksum mismatch: " + name)
    for name in manifest.get("missingTracked", []):
        if destination.joinpath(*safe_relative(name).parts).exists():
            raise ValueError("Deleted tracked file was unexpectedly restored: " + name)
    if run_git("rev-parse", "HEAD", cwd=destination) != manifest["head"]:
        raise ValueError("Restored Git HEAD does not match captured HEAD")
    if run_git("branch", "--show-current", cwd=destination) != manifest["branch"]:
        raise ValueError("Restored branch does not match captured branch")
    if digest(destination / ".git" / "index") != manifest["git-indexSha256"]:
        raise ValueError("Restored Git index does not match captured index")


def verify_backend(backend):
    manifest = json.loads((backend / "backend-manifest.json").read_text(encoding="utf-8"))
    for name, metadata in manifest["files"].items():
        path = backend.joinpath(*safe_relative(name).parts)
        if not path.is_file() or path.stat().st_size != metadata["size"] or digest(path) != metadata["sha256"]:
            raise ValueError("Backend baseline checksum mismatch: " + name)
        if path.suffix == ".zip":
            with zipfile.ZipFile(path) as archive:
                if archive.testzip():
                    raise ValueError("Deployed function source archive CRC check failed")
    return {"filesVerified": len(manifest["files"]), "functionsCaptured": manifest["functionCount"],
            "functionSourcesCaptured": manifest["functionsWithSourceArchive"],
            "dataExportCaptured": manifest["dataExportCaptured"],
            "productionRestoreDrillPerformed": manifest["productionRestoreDrillPerformed"]}


def verify_cloud_evidence(manifest_path):
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for name, metadata in manifest["files"].items():
        path = manifest_path.parent.joinpath(*safe_relative(name).parts)
        if not path.is_file() or path.stat().st_size != metadata["size"] or digest(path) != metadata["sha256"]:
            raise ValueError("Cloud recovery evidence checksum mismatch: " + name)
    return {"filesVerified": len(manifest["files"]), "exportUri": manifest.get("exportUri"),
            "snapshotTime": manifest.get("snapshotTime"), "exportVerified": manifest.get("exportVerified"),
            "exactSnapshotContentVerified": manifest.get("exactSnapshotContentVerified"),
            "ownedDrillDatabaseDeletedVerified": manifest.get("ownedDrillDatabaseDeletedVerified"),
            "liveCloudRechecked": False}


def restore(backup, destination, manifest):
    original = Path(manifest["workspace"]).resolve()
    if destination == original or original in destination.parents:
        raise ValueError("Restore destination must be outside the active workspace")
    if destination.exists():
        raise ValueError("Restore destination must be a NEW directory that does not exist")
    destination.parent.mkdir(parents=True, exist_ok=True)
    run_git("clone", "--no-checkout", str(backup / "history.bundle"), str(destination))
    run_git("config", "core.autocrlf", "false", cwd=destination)
    if manifest["branch"]:
        run_git("checkout", "--force", "-B", manifest["branch"], manifest["head"], cwd=destination)
    else:
        run_git("checkout", "--force", "--detach", manifest["head"], cwd=destination)
    # A Git bundle contains reachable commits, not uncommitted staged blobs.
    # Materialize staged objects before restoring the original index that points
    # at them. Applying to the index does not overwrite archived workspace bytes.
    if (backup / "staged.patch").stat().st_size:
        run_git("apply", "--cached", "--binary", str(backup / "staged.patch"), cwd=destination)
    for name in manifest.get("missingTracked", []):
        path = destination.joinpath(*safe_relative(name).parts)
        if path.is_file():
            path.unlink()
    with zipfile.ZipFile(backup / "workspace.zip") as archive:
        for member in archive.infolist():
            if not member.is_dir():
                name = safe_relative(member.filename)
                path = destination.joinpath(*name.parts)
                path.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(member) as source, path.open("wb") as target:
                    shutil.copyfileobj(source, target)
    shutil.copyfile(backup / "git-index", destination / ".git" / "index")
    verify_restore(destination, manifest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("backup", type=Path)
    parser.add_argument("--destination", type=Path, help="New directory for an offline restoration drill")
    parser.add_argument("--report", type=Path, help="Optional verification report outside the restored directory")
    parser.add_argument("--backend-baseline", type=Path, help="Also verify captured deployed function sources/configuration")
    parser.add_argument("--cloud-evidence", type=Path, action="append", default=[], help="Verify a cloud backup/drill manifest and its saved evidence (repeatable)")
    args = parser.parse_args()
    backup = args.backup.resolve()
    manifest = verify_backup(backup)
    report = {"verified": True, "head": manifest["head"], "branch": manifest["branch"],
              "filesVerified": len(manifest["files"]), "deletedPathsVerified": len(manifest.get("missingTracked", [])),
              "archiveVerified": True, "restored": False}
    if args.backend_baseline:
        report["backendBaseline"] = verify_backend(args.backend_baseline.resolve())
    if args.cloud_evidence:
        report["cloudEvidence"] = [verify_cloud_evidence(path.resolve()) for path in args.cloud_evidence]
    if args.destination:
        destination = args.destination.resolve()
        if args.report and (args.report.resolve() == destination or destination in args.report.resolve().parents):
            raise ValueError("Verification report must be outside the restored directory")
        restore(backup, destination, manifest)
        report.update(restored=True, destination=str(destination), gitIndexVerified=True)
    if args.report:
        args.report.resolve().write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("Rollback verification failed: " + str(error), file=sys.stderr)
        sys.exit(1)
