#!/usr/bin/env python3
"""Side-build and notarize a Primboard candidate. Never install or open user data."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

TEAM = "Y6CQ4SWPWM"
IDENTITY = "Developer ID Application: Eidos AGI LLC (" + TEAM + ")"
BUNDLE = "sh.prims.paste"
ROOT = Path(__file__).resolve().parent.parent


class ReleaseError(Exception):
    pass


def run(*args, cwd=None, timeout=120, stdout_only=False):
    result = subprocess.run([str(arg) for arg in args], cwd=cwd, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=timeout)
    if result.returncode:
        raise ReleaseError("Command failed: " + str(args[0]) + "\n" + result.stderr + result.stdout)
    return result.stdout if stdout_only else result.stdout + result.stderr


def command_json(*args):
    # notarytool's machine-readable stdout must not be mixed with diagnostics.
    result = subprocess.run([str(arg) for arg in args], capture_output=True,
                            text=True, timeout=120)
    if result.returncode:
        raise ReleaseError(result.stderr or result.stdout)
    return json.loads(result.stdout)


def save(path, value):
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def bundle_digest(app):
    entries = []
    for path in sorted(app.rglob("*")):
        if path.is_symlink():
            raise ReleaseError("Unexpected symlink in candidate: " + str(path))
        entries.append([str(path.relative_to(app)), path.stat().st_mode & 0o777,
                        sha256(path) if path.is_file() else None])
    return hashlib.sha256(json.dumps(entries).encode()).hexdigest()


def require_mac():
    if platform.system() != "Darwin" or int(platform.mac_ver()[0].split(".")[0]) < 14:
        raise ReleaseError("Primboard releases require macOS 14 or newer.")


def preflight(root):
    require_mac()
    for name in ("git", "tar", "swift", "security", "codesign", "ditto", "xcrun", "spctl"):
        if not shutil.which(name):
            raise ReleaseError("Required command is missing: " + name)
    identities = run("security", "find-identity", "-v", "-p", "codesigning")
    matches = re.findall(r'\b([A-Fa-f0-9]{40})\s+"' + re.escape(IDENTITY) + r'"', identities)
    if len(matches) != 1:
        raise ReleaseError("Need exactly one usable company signing identity: " + IDENTITY
                           + ". No app or notebook has been changed.")
    if run("git", "status", "--porcelain", "--untracked-files=normal", cwd=root).strip():
        raise ReleaseError("Use a clean committed checkout; preserve local work first.")
    source_sha = run("git", "rev-parse", "HEAD", cwd=root).strip()
    if not re.fullmatch(r"[a-f0-9]{40}", source_sha):
        raise ReleaseError("Cannot determine full source commit.")
    return matches[0], source_sha


def assemble(source, bin_dir, app):
    info = plistlib.loads((source / "Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != BUNDLE or info.get("CFBundleExecutable") != "PrimsPaste":
        raise ReleaseError("Compatibility-sensitive app identity changed.")
    resources = app / "Contents/Resources"
    (resources / "Fonts").mkdir(parents=True)
    (app / "Contents/MacOS").mkdir()
    (app / "Contents/Helpers").mkdir()
    for product, folder in (("PrimsPaste", "MacOS"), ("prims-paste", "Helpers")):
        destination = app / "Contents" / folder / product
        shutil.copy2(bin_dir / product, destination)
        destination.chmod(0o755)
    shutil.copy2(source / "Info.plist", app / "Contents/Info.plist")
    shutil.copy2(source / "brand/AppIcon.icns", resources / "AppIcon.icns")
    shutil.copy2(source / "brand/mark-paste.png", resources / "PasteMark.png")
    fonts = sorted((source / "brand/fonts").glob("*.ttf"))
    if not fonts:
        raise ReleaseError("Missing bundled fonts.")
    for font in fonts:
        shutil.copy2(font, resources / "Fonts" / font.name)
    # Include the font license with every candidate.
    shutil.copy2(source / "brand/fonts/OFL.txt", resources / "Fonts/OFL.txt")
    (app / "Contents/PkgInfo").write_bytes(b"APPL????")


def verify_signature(app):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != BUNDLE or info.get("CFBundleExecutable") != "PrimsPaste":
        raise ReleaseError("Candidate app identity mismatch.")
    for target in (app / "Contents/Helpers/prims-paste", app):
        run("codesign", "--verify", "--deep", "--strict", "--verbose=2", target)
        metadata = run("codesign", "-dv", "--verbose=4", target)
        for expected in ("TeamIdentifier=" + TEAM, "Authority=" + IDENTITY):
            if expected not in metadata.splitlines():
                raise ReleaseError("Signing identity mismatch: " + str(target))
        if "(runtime)" not in metadata or not re.search(r"^Timestamp=.+", metadata, re.M):
            raise ReleaseError("Missing hardened runtime or secure timestamp.")
        entitlements = run("codesign", "-d", "--entitlements", ":-", target)
        if "<plist" in entitlements:
            start = entitlements.index("<plist")
            end = entitlements.index("</plist>", start) + len("</plist>")
            if plistlib.loads(entitlements[start:end].encode()).get("com.apple.security.get-task-allow"):
                raise ReleaseError("Debug entitlement is forbidden in a release candidate.")


def zip_app(app, destination):
    if destination.exists():
        raise ReleaseError("Refusing to overwrite an existing archive: " + str(destination))
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, destination)


def build(root):
    identity, source_sha = preflight(root)  # Before building, quitting, or replacing anything.
    parent = root / ".build/release-candidates"
    parent.mkdir(parents=True, exist_ok=True)
    candidate = Path(tempfile.mkdtemp(prefix=source_sha[:12] + "-", dir=parent))
    print("Candidate workspace: " + str(candidate), flush=True)
    record = {"schema_version": 1, "state": "building", "source_sha": source_sha,
              "team_id": TEAM, "bundle_id": BUNDLE, "architecture": platform.machine(),
              "macos": platform.mac_ver()[0], "installed": False,
              "existing_store_acceptance": "not_run", "tcc_acceptance": "not_run",
              "fresh_download_acceptance": "not_run"}
    save(candidate / "release.json", record)
    source = candidate / "source"
    source.mkdir()
    run("git", "archive", "--format=tar", "--output", candidate / "source.tar", source_sha, cwd=root)
    run("tar", "-xf", candidate / "source.tar", "-C", source)
    record["swift_version"] = run("swift", "--version").strip()
    for command in (("swift", "test", "--parallel"), ("swift", "build", "-c", "release")):
        output = run(*command, cwd=source, timeout=1200)
        (candidate / ("tests.log" if command[1] == "test" else "build.log")).write_text(output)
    bin_dir = Path(run("swift", "build", "-c", "release", "--show-bin-path", cwd=source, stdout_only=True).strip())
    app = candidate / "Primboard.app"
    assemble(source, bin_dir, app)
    run(app / "Contents/MacOS/PrimsPaste", "--selftest")
    # Sign nested code first. --deep is used only for verification, never signing.
    run("codesign", "--force", "--options", "runtime", "--timestamp", "--sign", identity,
        app / "Contents/Helpers/prims-paste")
    run("codesign", "--force", "--options", "runtime", "--timestamp", "--sign", identity,
        "--entitlements", source / "PrimsPaste.entitlements", app)
    verify_signature(app)
    run(app / "Contents/MacOS/PrimsPaste", "--selftest")
    archive = candidate / "submission.zip"
    zip_app(app, archive)
    record.update(state="signed-candidate", signed_bundle_sha256=bundle_digest(app),
                  submission_sha256=sha256(archive))
    save(candidate / "release.json", record)
    print("Signed candidate only; installed app and notebook unchanged.\n" + str(candidate))
    return candidate


def notarize(candidate, profile, recovery_id=None):
    require_mac()
    candidate = candidate.resolve()
    record = json.loads((candidate / "release.json").read_text())
    app = candidate / "Primboard.app"
    archive = candidate / "submission.zip"
    if record.get("state") not in ("signed-candidate", "submitted", "notarized-candidate"):
        raise ReleaseError("Candidate did not finish signing.")
    if sha256(archive) != record["submission_sha256"] or bundle_digest(app) != record["signed_bundle_sha256"]:
        raise ReleaseError("Candidate changed since signing; refusing notarization.")
    verify_signature(app)
    if record["state"] == "notarized-candidate":
        if sha256(candidate / record["final_archive"]) != record["final_sha256"]:
            raise ReleaseError("Final archive has changed.")
        print("Already notarized; installed acceptance remains separate.")
        return 0
    auth = ("--keychain-profile", profile)
    submission = candidate / "submission.json"
    intent = candidate / "submission-started.json"
    recovery_id = recovery_id or record.get("submission_id")
    if not submission.exists():
        if recovery_id:
            # Apple log's archive hash is checked below before any stapling/promotion.
            save(submission, {"id": str(uuid.UUID(recovery_id)), "recovered": True})
        else:
            if intent.exists():
                raise ReleaseError("An upload was attempted but its ID was not recorded. Recover its ID with "
                                   "notarytool history and retry with --submission-id; do not resubmit.")
            command_json("xcrun", "notarytool", "history", *auth, "--output-format", "json")
            save(intent, {"submission_sha256": record["submission_sha256"]})
            # Write stdout directly so a returned submission ID survives later failures.
            with submission.open("x") as stream:
                result = subprocess.run(["xcrun", "notarytool", "submit", str(archive), *auth,
                                         "--output-format", "json"], stdout=stream,
                                        stderr=subprocess.PIPE, text=True, timeout=120)
            if result.returncode:
                raise ReleaseError("Upload did not finish cleanly. Preserve submission records and recover "
                                   "the existing ID before retrying.\n" + result.stderr)
    try:
        submission_id = str(uuid.UUID(json.loads(submission.read_text())["id"]))
    except (ValueError, KeyError):
        if not recovery_id:
            raise ReleaseError("Missing submission ID; recover it using notarytool history and --submission-id.")
        submission_id = str(uuid.UUID(recovery_id))
        # Preserve the original response, including partial output, for diagnosis.
        save(candidate / "submission-recovered.json", {"id": submission_id})
    record.update(state="submitted", submission_id=submission_id)
    save(candidate / "release.json", record)
    status = command_json("xcrun", "notarytool", "info", submission_id, *auth, "--output-format", "json")
    save(candidate / "notary-status.json", status)
    if status.get("status") != "Accepted":
        if status.get("status") != "In Progress":
            raise ReleaseError("Notarization did not accept this candidate: " + str(status.get("status")))
        print("Notarization status: " + str(status.get("status")) + "; rerun the same command to check this ID.")
        return 3
    log_path = candidate / "notary-log.json"
    if log_path.exists():
        log_path.rename(candidate / ("notary-log-" + uuid.uuid4().hex + ".json"))
    run("xcrun", "notarytool", "log", submission_id, *auth, log_path)
    log = json.loads(log_path.read_text())
    if (log.get("status") != "Accepted" or log.get("jobId") != submission_id
            or log.get("sha256", "").lower() != record["submission_sha256"]):
        raise ReleaseError("Apple's accepted log does not match this exact submitted archive.")
    # Leave the signed submission immutable; staple a separate copy for distribution.
    accepted = Path(tempfile.mkdtemp(prefix="accepted-", dir=candidate))
    final_app = accepted / "Primboard.app"
    run("ditto", app, final_app)
    run("xcrun", "stapler", "staple", final_app)
    run("xcrun", "stapler", "validate", final_app)
    verify_signature(final_app)
    run("spctl", "--assess", "--type", "execute", "--verbose=4", final_app)
    if shutil.which("syspolicy_check"):
        run("syspolicy_check", "distribution", final_app)
    final_archive = accepted / ("Primboard-" + record["source_sha"][:12] + "-" + record["architecture"] + ".zip")
    zip_app(final_app, final_archive)
    extracted = accepted / "extracted"
    run("ditto", "-x", "-k", final_archive, extracted)
    extracted_app = extracted / "Primboard.app"
    run("xcrun", "stapler", "validate", extracted_app)
    verify_signature(extracted_app)
    run("spctl", "--assess", "--type", "execute", "--verbose=4", extracted_app)
    run(extracted_app / "Contents/MacOS/PrimsPaste", "--selftest")
    record.update(state="notarized-candidate", final_archive=str(final_archive.relative_to(candidate)),
                  final_sha256=sha256(final_archive))
    save(candidate / "release.json", record)
    print("Notarized candidate: " + str(final_archive)
          + "\nInstalled-store, TCC, and fresh-download acceptance are still required.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("preflight", help="Check macOS, toolchain, usable signing identity, and clean source")
    commands.add_parser("build", help="Build/test/sign in an isolated directory; never install")
    notary = commands.add_parser("notarize", help="Submit once or resume a candidate; never install")
    notary.add_argument("candidate", type=Path)
    notary.add_argument("--notary-profile", required=True, help="Existing authorized Keychain profile name")
    notary.add_argument("--submission-id", help="Recover an interrupted upload; Apple's archive hash must match")
    args = parser.parse_args()
    try:
        if args.command == "preflight":
            _, source_sha = preflight(ROOT)
            print("Preflight passed: " + source_sha + " / " + IDENTITY)
            return 0
        if args.command == "build":
            build(ROOT)
            return 0
        return notarize(args.candidate, args.notary_profile, args.submission_id)
    except (ReleaseError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print("BLOCKED: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
