"""Regression checks for build/edit races; these tests do not require Docker."""
import contextlib
import hashlib
import importlib.util
import io
import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock


spec = importlib.util.spec_from_file_location("memory_runner", pathlib.Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

IMAGE_A = "sha256:" + "a" * 64
IMAGE_B = "sha256:" + "b" * 64


def image_info(fingerprint, image_id=IMAGE_A):
    return {
        "Id": image_id,
        "Architecture": "arm64",
        "Config": {"Labels": {
            runner.INPUT_LABEL: fingerprint["inputDigest"],
            runner.PROVENANCE_LABEL: json.dumps(fingerprint),
        }},
    }


class BuildProvenanceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="debrify-runner-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.here = self.root / "tool/webdav_memory_stress"
        self.here.mkdir(parents=True)
        self.source_name = "services/example.dart"
        self.source = self.root / "lib" / self.source_name
        self.source.parent.mkdir(parents=True)
        self.source.write_bytes(b"original source\n")
        for name in runner.BUILD_FILES:
            (self.here / name).write_text(name + " original\n")
        for name, value in [("ROOT", self.root), ("HERE", self.here),
                            ("SOURCES", [self.source_name])]:
            patch = mock.patch.object(runner, name, value)
            patch.start()
            self.addCleanup(patch.stop)

    def test_edit_during_copy_cannot_label_old_code_with_new_fingerprint(self):
        original = self.source.read_bytes()
        real_copy = shutil.copy2
        captured = {}

        def copy_then_edit(source, destination):
            result = real_copy(source, destination)
            if source == self.source:
                self.source.write_bytes(b"edited while preparing build\n")
            return result

        def build_command(*args):
            context = pathlib.Path(args[-1])
            labels = dict(args[i + 1].split("=", 1)
                          for i, arg in enumerate(args) if arg == "--label")
            captured["labels"] = labels
            captured["bytes"] = (context / "lib" / self.source_name).read_bytes()
            pathlib.Path(args[args.index("--iidfile") + 1]).write_text(IMAGE_A)

        with mock.patch.object(runner.shutil, "copy2", side_effect=copy_then_edit), \
                mock.patch.object(runner, "command", side_effect=build_command):
            self.assertEqual(runner.build(), IMAGE_A)
        copied = json.loads(captured["labels"][runner.PROVENANCE_LABEL])
        self.assertEqual(captured["bytes"], original)
        self.assertEqual(copied["sourceSha256"][self.source_name], hashlib.sha256(original).hexdigest())
        self.assertNotEqual(copied, runner.input_fingerprint())
        with self.assertRaisesRegex(SystemExit, "does not match the current sources"):
            runner.verified_fingerprint(image_info(copied))

    def test_unchanged_copy_is_accepted_and_reports_every_build_input(self):
        context = self.root / "copied"
        context.mkdir()
        for name in runner.BUILD_FILES:
            shutil.copy2(self.here / name, context / name)
        target = context / "lib" / self.source_name
        target.parent.mkdir(parents=True)
        shutil.copy2(self.source, target)
        copied = runner.input_fingerprint(context)
        self.assertEqual(copied, runner.input_fingerprint())
        self.assertEqual(len(copied["buildInputSha256"]), len(runner.BUILD_FILES) + 1)
        self.assertEqual(runner.verified_fingerprint(image_info(copied)), copied)

    def test_old_image_without_copied_provenance_requires_rebuild(self):
        with self.assertRaisesRegex(SystemExit, "rebuild without --skip-build"):
            runner.verified_fingerprint({"Config": {"Labels": None}})

    def test_retagging_and_late_edits_cannot_change_report_or_selected_image(self):
        for skip_build in (False, True):
            with self.subTest(skip_build=skip_build):
                self.source.write_bytes(b"source at validation\n")
                fingerprint = runner.input_fingerprint()
                report = self.root / f"report-{skip_build}.jsonl"
                tag = [IMAGE_A]

                def inspect(reference):
                    # A new build's iidfile result must win over a replaced tag.
                    actual = tag[0] if reference == runner.IMAGE else reference
                    return image_info(fingerprint, actual)

                def build():
                    tag[0] = IMAGE_B  # A second build finishes just after ours.
                    return IMAGE_A

                def capture(*args):
                    if args[:2] == ("docker", "info"):
                        # Validation has finished. Change both the workspace
                        # and the tag before metadata and test containers exist.
                        self.source.write_bytes(b"edited after image validation\n")
                        tag[0] = IMAGE_B
                        return json.dumps({"ServerVersion": "test"})
                    return "git-head-context-only\n"

                argv = ["run.py", "--report", str(report), "--case", "limit-control"]
                if skip_build:
                    argv.append("--skip-build")
                with mock.patch("sys.argv", argv), \
                        mock.patch.object(runner, "build", side_effect=build) as build_mock, \
                        mock.patch.object(runner, "inspect_image", side_effect=inspect) as inspect_mock, \
                        mock.patch.object(runner, "capture", side_effect=capture), \
                        mock.patch.object(runner, "run_case", return_value=True) as case_mock, \
                        contextlib.redirect_stdout(io.StringIO()), \
                        self.assertRaises(SystemExit) as exited:
                    runner.main()
                self.assertEqual(exited.exception.code, 0)
                self.assertEqual(build_mock.call_count, 0 if skip_build else 1)
                inspect_mock.assert_called_once_with(runner.IMAGE if skip_build else IMAGE_A)
                case_mock.assert_called_once_with(runner.CASES[0], report, 900, IMAGE_A, False)
                metadata = json.loads(report.read_text())
                self.assertEqual(metadata["imageId"], IMAGE_A)
                self.assertEqual(metadata["sourceSha256"], fingerprint["sourceSha256"])
                self.assertNotEqual(metadata["sourceSha256"], runner.input_fingerprint()["sourceSha256"])

    def test_case_uses_pinned_id_and_rejects_an_unexpected_actual_image(self):
        for actual_id in (IMAGE_A, IMAGE_B):
            with self.subTest(actual_id=actual_id):
                report = self.root / f"case-{actual_id[-1]}.jsonl"
                case = runner.CASES[1]
                limit = case[1] * 1024 * 1024
                info = {
                    "Image": actual_id,
                    "HostConfig": {"Memory": limit, "MemorySwap": limit, "NanoCpus": 1_000_000_000},
                    "State": {"OOMKilled": False, "ExitCode": 0},
                }
                events = [
                    {"event": "start", "cgroupLimit": str(limit), "cgroupSwapLimit": "0"},
                    {"event": "result", "verified": True},
                ]
                logs = subprocess.CompletedProcess([], 0, "\n".join(map(json.dumps, events)), "")
                with mock.patch.object(runner, "command") as commands, \
                        mock.patch.object(runner, "capture", return_value=json.dumps([info])), \
                        mock.patch.object(runner.subprocess, "run", return_value=logs), \
                        contextlib.redirect_stdout(io.StringIO()):
                    passed = runner.run_case(case, report, 900, IMAGE_A)
                create = commands.call_args_list[0].args
                self.assertEqual(create[-len(case[3]) - 1], IMAGE_A)
                self.assertNotIn(runner.IMAGE, create)
                result = json.loads(report.read_text())
                self.assertEqual(result["imageId"], actual_id)
                self.assertEqual(result["imageVerified"], actual_id == IMAGE_A)
                self.assertEqual(passed, actual_id == IMAGE_A)


if __name__ == "__main__":
    unittest.main()
