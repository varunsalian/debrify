#!/usr/bin/env python3
"""Compile production Dart code, then exercise it under Linux cgroup limits."""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import tempfile
import time
import uuid

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
IMAGE = "debrify-webdav-memory-stress:local"
INPUT_LABEL = "dev.debrify.memory-input"
PROVENANCE_LABEL = "dev.debrify.memory-provenance"
BUILD_FILES = ("Dockerfile", "pubspec.yaml", "pubspec.lock", "worker.dart")
SOURCES = [
    "models/home_collection.dart",
    "models/webdav_item.dart",
    "utils/canonical_json.dart",
    "services/profiles/local_backup/local_backup_zip.dart",
    "services/transfer/transfer_io.dart",
    "services/transfer/streaming_encrypted_file.dart",
    "services/webdav_protocol_client.dart",
    "services/webdav_sync/webdav_sync_codec.dart",
    "services/webdav_sync/webdav_sync_models.dart",
    "services/webdav_sync/webdav_sync_hot_models.dart",
    "services/webdav_sync/webdav_sync_collection_sections.dart",
]
# Probe cases record a boundary; an OOM is a finding, never a passing operation.
# They also fail the run unless the caller explicitly requests exploratory mode.
CASES = [
    ("limit-control", 128, "oom", ["oom-control", "384"]),
    ("archive-512", 128, "pass", ["pipeline", "512", "mixed", "key", "1"]),
    ("archive-1024", 128, "pass", ["pipeline", "1024", "mixed", "key", "1"]),
    ("incompressible-128", 128, "pass", ["pipeline", "128", "random", "key", "1"]),
    ("high-expansion-512", 128, "pass", ["pipeline", "512", "zeros", "key", "1"]),
    ("password-128", 128, "pass", ["pipeline", "128", "mixed", "password", "1"]),
    ("password-128-at-256", 256, "pass", ["pipeline", "128", "mixed", "password", "1"]),
    ("password-512", 128, "pass", ["pipeline", "512", "mixed", "password", "1"]),
    ("password-repeat-64", 128, "pass", ["pipeline", "64", "mixed", "password", "5"]),
    ("sync-unlock-128", 128, "pass", ["pipeline", "128", "mixed", "sync", "1"]),
    ("repeat-64", 128, "pass", ["pipeline", "64", "mixed", "key", "5"]),
    ("faults-64", 128, "pass", ["pipeline", "64", "mixed", "faults", "1"]),
    ("collections-64-at-128", 128, "probe", ["collections", "64"]),
    ("collections-513-at-256", 256, "probe", ["collections", "513"]),
    ("collections-513-at-512", 512, "probe", ["collections", "513"]),
]


def command(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def capture(*args):
    return command(*args, stdout=subprocess.PIPE).stdout


def input_fingerprint(context=None):
    """Hash each file once; a build context is the authoritative copied input."""
    digest = hashlib.sha256()
    inputs = [(str((HERE / name).relative_to(ROOT)), name) for name in BUILD_FILES]
    inputs += [(f"lib/{name}", f"lib/{name}") for name in SOURCES]
    hashes = {}
    for repository_name, context_name in inputs:
        path = ROOT / repository_name if context is None else context / context_name
        contents = path.read_bytes()
        digest.update(repository_name.encode())
        digest.update(b"\0")
        digest.update(contents)
        digest.update(b"\0")
        hashes[repository_name] = hashlib.sha256(contents).hexdigest()
    return {
        "inputDigest": digest.hexdigest(),
        "sourceSha256": {name: hashes[f"lib/{name}"] for name in SOURCES},
        "workerSha256": hashes[str((HERE / "worker.dart").relative_to(ROOT))],
        "buildInputSha256": hashes,
    }


def build():
    # Only the worker, pinned dependencies and selected production source files
    # enter the local Docker build. No Flutter SDK, app secrets or user data.
    with tempfile.TemporaryDirectory(prefix="debrify-memory-build-") as temp:
        context = pathlib.Path(temp) / "context"
        context.mkdir()
        image_id_file = pathlib.Path(temp) / "image-id"
        for name in BUILD_FILES:
            shutil.copy2(HERE / name, context / name)
        for relative in SOURCES:
            target = context / "lib" / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / "lib" / relative, target)
        fingerprint = input_fingerprint(context)
        command(
            "docker", "build", "--iidfile", str(image_id_file),
            "--label", f"{INPUT_LABEL}={fingerprint['inputDigest']}",
            "--label", f"{PROVENANCE_LABEL}={json.dumps(fingerprint, sort_keys=True)}",
            "-t", IMAGE, str(context),
        )
        # Another build can replace IMAGE while this build is running. Docker's
        # per-invocation iidfile identifies the image that this build produced.
        return image_id_file.read_text().strip()


def inspect_image(reference):
    return json.loads(capture("docker", "image", "inspect", reference))[0]


def verified_fingerprint(image):
    labels = image["Config"].get("Labels") or {}
    try:
        fingerprint = json.loads(labels[PROVENANCE_LABEL])
    except (KeyError, TypeError, json.JSONDecodeError):
        raise SystemExit("Image lacks input provenance; rebuild without --skip-build")
    if (fingerprint != input_fingerprint()
            or labels.get(INPUT_LABEL) != fingerprint.get("inputDigest")):
        raise SystemExit(
            "The image does not match the current sources; rebuild without --skip-build"
        )
    # Reports use the image's copied inputs, even if the workspace changes after
    # this check. Never re-read live source files to describe the compiled image.
    return fingerprint


def run_case(case, report, timeout, image_id, allow_probe_oom=False):
    label, limit, expected, arguments = case
    name = f"debrify-memory-{uuid.uuid4().hex[:12]}"
    limit_bytes = limit * 1024 * 1024
    started = time.monotonic()
    created = False
    timed_out = False
    try:
        command(
            "docker", "create", "--name", name,
            "--memory", str(limit_bytes), "--memory-swap", str(limit_bytes),
            "--cpus", "1", "--network", "none", "--pids-limit", "128",
            image_id, *arguments, stdout=subprocess.DEVNULL,
        )
        created = True
        # Compilation is outside this budget; the actual AOT process and its
        # loopback HTTP server, file cache and runtime are inside it.
        command("docker", "start", name, stdout=subprocess.DEVNULL)
        try:
            command("docker", "wait", name, stdout=subprocess.DEVNULL, timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            command("docker", "kill", name, stdout=subprocess.DEVNULL)
        info = json.loads(capture("docker", "inspect", name))[0]
        logs = subprocess.run(
            ["docker", "logs", name], text=True, capture_output=True, check=True,
        )
        events = []
        for line in logs.stdout.splitlines():
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                pass
        active_stage = None
        last_completed_stage = None
        for event in events:
            if event.get("event") == "stage-start":
                active_stage = event["stage"]
            elif event.get("event") == "stage-end":
                last_completed_stage = event["stage"]
                active_stage = None
        config = info["HostConfig"]
        image_verified = info["Image"] == image_id
        limits_verified = (
            config["Memory"] == limit_bytes
            and config["MemorySwap"] == limit_bytes
            and config["NanoCpus"] == 1_000_000_000
            and bool(events)
            and events[0].get("cgroupLimit") == str(limit_bytes)
            and events[0].get("cgroupSwapLimit") == "0"
        )
        verified = any(e.get("event") == "result" and e.get("verified") for e in events)
        state = info["State"]
        if timed_out:
            outcome = "timeout"
        elif state["OOMKilled"]:
            outcome = "oom"
        elif state["ExitCode"] == 0 and verified:
            outcome = "pass"
        else:
            outcome = "error"
        acceptable = image_verified and limits_verified and (
            outcome == expected or (expected == "probe" and (
                outcome == "pass" or (allow_probe_oom and outcome == "oom")
            ))
        )
        result = {
            "case": label, "limitMiB": limit, "expected": expected,
            "outcome": outcome, "limitsVerified": limits_verified,
            "imageId": info["Image"], "imageVerified": image_verified,
            "expectationMet": acceptable, "exitCode": state["ExitCode"],
            "oomKilled": state["OOMKilled"], "elapsedSeconds": round(time.monotonic() - started, 2),
            "peakRssBytes": max((e.get("peakRssBytes", 0) for e in events), default=0),
            "lastStage": next((e.get("stage") for e in reversed(events) if "stage" in e), None),
            "activeStageAtExit": active_stage,
            "lastCompletedStage": last_completed_stage,
            "events": events, "stderr": logs.stderr,
        }
        with report.open("a") as output:
            output.write(json.dumps(result) + "\n")
        print(json.dumps({k: v for k, v in result.items() if k not in ("events", "stderr")}), flush=True)
        return acceptable
    finally:
        if created:
            subprocess.run(["docker", "rm", "-f", name], check=False, stdout=subprocess.DEVNULL)


def main():
    runner_sha256 = hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", action="append", choices=[c[0] for c in CASES])
    parser.add_argument("--skip-build", action="store_true", help="Reuse an image you just built")
    parser.add_argument("--allow-probe-oom", action="store_true",
                        help="Exploratory run: record probe OOMs without failing the suite")
    parser.add_argument("--timeout", type=int, default=900, help="Per-case timeout in seconds")
    parser.add_argument("--report", type=pathlib.Path, required=True, help="New JSONL result file")
    args = parser.parse_args()
    # Never overwrite an existing run, even if setup fails.
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open("x"):
        pass
    # Resolve the mutable tag only once for --skip-build. A new build instead
    # returns its own immutable ID, so concurrent retagging cannot select it.
    selected_image = inspect_image(IMAGE if args.skip_build else build())
    fingerprint = verified_fingerprint(selected_image)
    image_id = selected_image["Id"]
    metadata = {
        "event": "environment", "utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "docker": json.loads(capture("docker", "info", "--format", "{{json .}}"))["ServerVersion"],
        "imageId": image_id,
        "imageArchitecture": selected_image["Architecture"],
        "gitHead": capture("git", "-C", str(ROOT), "rev-parse", "HEAD").strip(),
        **fingerprint,
        "runnerSha256": runner_sha256,
        "allowProbeOom": args.allow_probe_oom,
    }
    with args.report.open("a") as output:
        output.write(json.dumps(metadata) + "\n")
    passed = True
    for case in CASES:
        if args.case is None or case[0] in args.case:
            print(f"Running {case[0]} at {case[1]} MiB, no swap, one CPU", flush=True)
            passed = run_case(case, args.report, args.timeout, image_id, args.allow_probe_oom) and passed
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
