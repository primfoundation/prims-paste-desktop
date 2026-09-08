"""Failure boundaries plus real bundle assembly on the macOS CI runner."""
import importlib.util
import json
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("mac_release", ROOT / "scripts/mac_release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)
SUBMISSION_ID = "11111111-2222-3333-4444-555555555555"


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "repo"
        self.source.mkdir()
        (self.source / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": release.BUNDLE, "CFBundleExecutable": "PrimsPaste"}))
        (self.source / "brand/fonts").mkdir(parents=True)
        for name in ("AppIcon.icns", "mark-paste.png", "fonts/test.ttf", "fonts/OFL.txt"):
            (self.source / "brand" / name).write_bytes(b"resource")
        self.bins = self.root / "bin"
        self.bins.mkdir()
        for name in ("PrimsPaste", "prims-paste"):
            (self.bins / name).write_bytes(b"binary")
        self.installed = self.root / "Applications/Primboard.app"
        self.installed.mkdir(parents=True)
        (self.installed / "working-app").write_bytes(b"keep app")
        self.notebook = self.root / "notebook"
        self.notebook.mkdir()
        (self.notebook / "index.json").write_bytes(b"keep original index")

    def assert_existing_untouched(self):
        self.assertEqual((self.installed / "working-app").read_bytes(), b"keep app")
        self.assertEqual((self.notebook / "index.json").read_bytes(), b"keep original index")

    def candidate(self):
        candidate = self.root / "candidate"
        candidate.mkdir()
        release.assemble(self.source, self.bins, candidate / "Primboard.app")
        (candidate / "submission.zip").write_bytes(b"original archive")
        record = {"state": "signed-candidate", "source_sha": "a" * 40, "architecture": "arm64",
                  "submission_sha256": release.sha256(candidate / "submission.zip"),
                  "signed_bundle_sha256": release.bundle_digest(candidate / "Primboard.app")}
        release.save(candidate / "release.json", record)
        return candidate

    def test_missing_private_key_aborts_before_build_or_output_creation(self):
        with patch.object(release, "require_mac"), patch.object(release.shutil, "which", return_value="tool"), \
                patch.object(release, "run", return_value="0 valid identities found") as command:
            with self.assertRaisesRegex(release.ReleaseError, "usable company signing identity"):
                release.build(self.source)
        self.assertEqual(command.call_count, 1)
        self.assertFalse((self.source / ".build").exists())
        self.assert_existing_untouched()

    def test_dirty_checkout_is_not_shipped(self):
        identity = '1) ' + "A" * 40 + ' "' + release.IDENTITY + '"'
        with patch.object(release, "require_mac"), patch.object(release.shutil, "which", return_value="tool"), \
                patch.object(release, "run", side_effect=[identity, " M Sources/Board.swift"]):
            with self.assertRaisesRegex(release.ReleaseError, "clean committed checkout"):
                release.build(self.source)
        self.assertFalse((self.source / ".build").exists())

    def test_packaging_keeps_executables_resources_license_and_identity(self):
        app = self.root / "new/Primboard.app"
        release.assemble(self.source, self.bins, app)
        self.assertEqual((app / "Contents/Helpers/prims-paste").stat().st_mode & 0o777, 0o755)
        self.assertEqual((app / "Contents/Resources/Fonts/OFL.txt").read_bytes(), b"resource")
        self.assertEqual(plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleIdentifier"], release.BUNDLE)
        self.assert_existing_untouched()

    def test_identity_change_refuses_bundle_assembly(self):
        (self.source / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "wrong"}))
        with self.assertRaisesRegex(release.ReleaseError, "identity changed"):
            release.assemble(self.source, self.bins, self.root / "new.app")
        self.assertFalse((self.root / "new.app").exists())

    def test_wrong_signer_rejects_candidate(self):
        app = self.candidate() / "Primboard.app"
        with patch.object(release, "run", side_effect=["", "TeamIdentifier=WRONG\n"]):
            with self.assertRaisesRegex(release.ReleaseError, "Signing identity mismatch"):
                release.verify_signature(app)

    def test_debug_entitlement_rejects_candidate(self):
        app = self.candidate() / "Primboard.app"
        metadata = "TeamIdentifier=" + release.TEAM + "\nAuthority=" + release.IDENTITY + "\nflags=0x10000(runtime)\nTimestamp=now\n"
        entitlements = plistlib.dumps({"com.apple.security.get-task-allow": True}).decode()
        with patch.object(release, "run", side_effect=["", metadata, entitlements]):
            with self.assertRaisesRegex(release.ReleaseError, "Debug entitlement"):
                release.verify_signature(app)

    def test_changed_candidate_never_submits(self):
        candidate = self.candidate()
        (candidate / "Primboard.app/Contents/Resources/PasteMark.png").write_bytes(b"changed")
        with patch.object(release, "require_mac"), patch.object(release, "command_json") as command:
            with self.assertRaisesRegex(release.ReleaseError, "changed since signing"):
                release.notarize(candidate, "existing-profile")
        command.assert_not_called()

    def test_interrupted_upload_cannot_silently_resubmit(self):
        candidate = self.candidate()
        release.save(candidate / "submission-started.json", {})
        with patch.object(release, "require_mac"), patch.object(release, "verify_signature"), \
                patch.object(release, "command_json") as command:
            with self.assertRaisesRegex(release.ReleaseError, "do not resubmit"):
                release.notarize(candidate, "existing-profile")
        command.assert_not_called()

    def test_pending_submission_resumes_same_id_without_new_upload(self):
        candidate = self.candidate()
        release.save(candidate / "submission.json", {"id": SUBMISSION_ID})
        with patch.object(release, "require_mac"), patch.object(release, "verify_signature"), \
                patch.object(release, "command_json", return_value={"status": "In Progress"}) as command, \
                patch.object(release, "run") as mutation:
            self.assertEqual(release.notarize(candidate, "existing-profile"), 3)
        self.assertEqual(command.call_args.args[2:4], ("info", SUBMISSION_ID))
        mutation.assert_not_called()
        self.assertNotIn("final_archive", json.loads((candidate / "release.json").read_text()))

    def test_rejected_submission_cannot_produce_distribution_archive(self):
        candidate = self.candidate()
        release.save(candidate / "submission.json", {"id": SUBMISSION_ID})
        with patch.object(release, "require_mac"), patch.object(release, "verify_signature"), \
                patch.object(release, "command_json", return_value={"status": "Invalid"}), \
                patch.object(release, "run") as mutation:
            with self.assertRaisesRegex(release.ReleaseError, "did not accept"):
                release.notarize(candidate, "existing-profile")
        mutation.assert_not_called()
        self.assert_existing_untouched()

    def test_accepted_log_for_different_archive_is_rejected(self):
        candidate = self.candidate()
        release.save(candidate / "submission.json", {"id": SUBMISSION_ID})
        def log_command(*args):
            self.assertEqual(args[1:3], ("notarytool", "log"))
            release.save(Path(args[-1]), {"status": "Accepted", "jobId": SUBMISSION_ID, "sha256": "wrong"})
        with patch.object(release, "require_mac"), patch.object(release, "verify_signature"), \
                patch.object(release, "command_json", return_value={"status": "Accepted"}), \
                patch.object(release, "run", side_effect=log_command) as command:
            with self.assertRaisesRegex(release.ReleaseError, "exact submitted archive"):
                release.notarize(candidate, "existing-profile")
        self.assertEqual(command.call_count, 1)
        self.assertFalse(list(candidate.glob("accepted-*")))

    def test_recovered_upload_id_persists_across_pending_checks(self):
        candidate = self.candidate()
        (candidate / "submission.json").write_text("partial response")
        with patch.object(release, "require_mac"), patch.object(release, "verify_signature"), \
                patch.object(release, "command_json", return_value={"status": "In Progress"}) as command:
            self.assertEqual(release.notarize(candidate, "existing-profile", SUBMISSION_ID), 3)
            self.assertEqual(release.notarize(candidate, "existing-profile"), 3)
        self.assertEqual(command.call_count, 2)
        self.assertEqual((candidate / "submission.json").read_text(), "partial response")

    def test_accepted_candidate_is_archived_after_stapling_and_unpack_verification(self):
        candidate = self.candidate()
        original_hash = release.bundle_digest(candidate / "Primboard.app")
        release.save(candidate / "submission.json", {"id": SUBMISSION_ID})
        final_apps = []
        def command(*args):
            args = [str(arg) for arg in args]
            if args[:3] == ["xcrun", "notarytool", "log"]:
                release.save(Path(args[-1]), {"status": "Accepted", "jobId": SUBMISSION_ID,
                             "sha256": release.sha256(candidate / "submission.zip")})
            elif args[:3] == ["xcrun", "stapler", "staple"]:
                (Path(args[-1]) / "ticket").write_bytes(b"accepted ticket")
                final_apps.append(Path(args[-1]))
            elif args[:3] == ["xcrun", "stapler", "validate"]:
                self.assertTrue((Path(args[-1]) / "ticket").exists())
            elif args[:2] == ["ditto", "-c"]:
                self.assertTrue((Path(args[-2]) / "ticket").exists())
                Path(args[-1]).write_bytes(b"archive with ticket")
            elif args[:2] == ["ditto", "-x"]:
                shutil.copytree(final_apps[0], Path(args[-1]) / "Primboard.app")
            elif args[0] == "ditto":
                shutil.copytree(args[1], args[2])
            return ""
        with patch.object(release, "require_mac"), patch.object(release, "verify_signature") as verify, \
                patch.object(release, "command_json", return_value={"status": "Accepted"}), \
                patch.object(release, "run", side_effect=command):
            self.assertEqual(release.notarize(candidate, "existing-profile"), 0)
        record = json.loads((candidate / "release.json").read_text())
        self.assertEqual(record["state"], "notarized-candidate")
        self.assertEqual(record["final_sha256"], release.sha256(candidate / record["final_archive"]))
        self.assertEqual(verify.call_count, 3)  # Original, stapled, and final ZIP's extracted app.
        self.assertEqual(release.bundle_digest(candidate / "Primboard.app"), original_hash)
        self.assert_existing_untouched()

    @unittest.skipUnless(platform.system() == "Darwin", "Real macOS binaries required")
    def test_real_release_binaries_selftest_inside_assembled_app(self):
        # CI builds these before running this suite; absence is a failure on macOS.
        app = self.root / "Real/Primboard.app"
        release.assemble(ROOT, ROOT / ".build/release", app)
        subprocess.run([str(app / "Contents/MacOS/PrimsPaste"), "--selftest"], check=True,
                       capture_output=True, text=True, timeout=60)


if __name__ == "__main__":
    unittest.main()
