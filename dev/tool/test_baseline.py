#!/usr/bin/env python3
"""Compare the suite's failures against a checked-in baseline, BY NAME.

A count gate ("no worse than 9 failures") passes when a new regression replaces
a repaired old failure. This records every failing test's `suite::name` so a
swap is as loud as an addition.

    python3 dev/tool/test_baseline.py            # compare against the baseline
    python3 dev/tool/test_baseline.py --record   # rewrite the baseline

Exit 0 when the failure set is identical or a strict subset (things got
better); exit 1 and print the delta otherwise.
"""
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
BASELINE = ROOT / "test" / "known_failures.txt"


class RunFailed(Exception):
    """The runner itself failed — a compile error, a crashed suite, no JSON.

    This is the difference between a gate and a rubber stamp: a run that dies
    before emitting events has an EMPTY failure set, which compares clean
    against any baseline. Nonzero exit with nothing parsed must be loud.
    """


def run() -> set[str]:
    proc = subprocess.run(
        ["flutter", "test", "--reporter", "json"],
        cwd=ROOT, capture_output=True, text=True,
    )
    tests: dict[int, str] = {}
    suites: dict[int, str] = {}
    test_suite: dict[int, int] = {}
    failed: set[str] = set()
    saw_done = False
    load_errors: list[str] = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        kind = ev.get("type")
        if kind == "done":
            saw_done = True
        elif kind == "error":
            # Kept only for the RunFailed diagnostic. These are NOT added to the
            # failure set: `error` fires for ordinary expectation failures too,
            # which already arrive as a testDone — and a suite that fails to
            # load arrives as a testDone on its synthetic "loading <path>" test,
            # so nothing is lost by ignoring them here.
            load_errors.append((ev.get("error") or "").splitlines()[0][:160])
        if kind == "suite":
            s = ev["suite"]
            path = s.get("path") or ""
            try:
                path = str(pathlib.Path(path).relative_to(ROOT))
            except ValueError:
                pass
            suites[s["id"]] = path
        elif kind == "testStart":
            t = ev["test"]
            tests[t["id"]] = t.get("name", "")
            test_suite[t["id"]] = t.get("suiteID", -1)
        elif kind == "testDone" and ev.get("result") != "success":
            # hidden == the synthetic (setUpAll)/(tearDownAll) wrappers
            if ev.get("hidden"):
                continue
            tid = ev["testID"]
            suite = suites.get(test_suite.get(tid, -1), "?")
            failed.add(f"{suite}::{tests.get(tid, '?')}")

    if not saw_done or (proc.returncode != 0 and not failed):
        raise RunFailed(
            f"flutter test exited {proc.returncode} with "
            f"{len(failed)} parsed failures and done={saw_done}.\n"
            + "\n".join(load_errors[:5])
            + ("\n--- stderr ---\n" + proc.stderr[-2000:] if proc.stderr else "")
        )
    return failed


def main() -> int:
    try:
        failed = run()
    except RunFailed as e:
        print(f"RUNNER FAILED — gate not satisfied.\n{e}", file=sys.stderr)
        return 2
    if "--record" in sys.argv:
        BASELINE.write_text(
            "# Pre-existing failures, compared BY NAME by dev/tool/test_baseline.py.\n"
            "# Regenerate deliberately: python3 dev/tool/test_baseline.py --record\n"
            + "\n".join(sorted(failed)) + "\n"
        )
        print(f"recorded {len(failed)} known failures -> {BASELINE.name}")
        return 0

    if not BASELINE.exists():
        print("no baseline; run with --record first", file=sys.stderr)
        return 1
    known = {
        ln.strip() for ln in BASELINE.read_text().splitlines()
        if ln.strip() and not ln.startswith("#")
    }
    new = failed - known
    fixed = known - failed
    for t in sorted(fixed):
        print(f"  FIXED (baseline is stale): {t}")
    for t in sorted(new):
        print(f"  NEW FAILURE: {t}")
    if new:
        print(f"\n{len(new)} new failure(s) against a baseline of {len(known)}.")
        return 1
    print(f"clean — {len(failed)}/{len(known)} known failures, no new ones.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
