#!/usr/bin/env python3
"""Repo-wide file-size ratchet for handwritten app code (AGENTS.md sizes).

A file over the limit must already be listed in the baseline and must not
grow past its recorded line count. Any other file may not exceed the limit.
Generated code and patched vendor packages (packages/) are exempt.

  python3 dev/tool/check_file_sizes.py           # check (CI)
  python3 dev/tool/check_file_sizes.py --update  # record shrinkage only

--update only lowers counts and drops files that are back under the limit;
it never raises a count or adds a file, so it cannot accept growth. A small
fix that must grow a listed file raises that file's count by hand in the same
commit, so the exception is visible in review (AGENTS.md: record the
exception and scope). Prefer extracting code instead.
"""
import re
import subprocess
import sys
from pathlib import Path

LIMIT = 800
ROOT = Path(__file__).resolve().parents[2]
BASELINE = ROOT / 'dev/tool/file_size_baseline.txt'
INCLUDE = re.compile(
    r'^(lib/.+\.dart'
    r'|android/app/src/.+\.(kt|java)'
    r'|(ios|macos|tvos)/Runner/.+\.(swift|m|mm|h)'
    r'|(linux|windows)/runner/.+\.(cc|cpp|c|h))$'
)
GENERATED = re.compile(
    r'\.(g|freezed|gr|mocks)\.dart$|[Gg]enerated_?[Pp]lugin_?[Rr]egistrant'
)


def measure():
    files = subprocess.run(
        ['git', 'ls-files'], cwd=ROOT, capture_output=True, text=True, check=True
    ).stdout.splitlines()
    sizes = {}
    for path in files:
        if not INCLUDE.match(path) or GENERATED.search(path):
            continue
        full = ROOT / path
        if full.is_file():
            with open(full, 'rb') as handle:
                sizes[path] = sum(1 for _ in handle)
    return sizes


def read_baseline():
    baseline = {}
    for line in BASELINE.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith('#'):
            count, path = line.split(None, 1)
            baseline[path] = int(count)
    return baseline


def write_baseline(baseline):
    header = (
        '# Files allowed over the size limit, with their maximum line count.\n'
        '# Maintained by dev/tool/check_file_sizes.py --update (shrink only).\n'
    )
    body = ''.join(
        f'{count} {path}\n'
        for path, count in sorted(baseline.items(), key=lambda kv: (-kv[1], kv[0]))
    )
    BASELINE.write_text(header + body)


def main():
    sizes = measure()
    baseline = read_baseline() if BASELINE.exists() else {}
    if '--update' in sys.argv:
        updated = {
            path: min(count, sizes[path])
            for path, count in baseline.items()
            if sizes.get(path, 0) > LIMIT
        }
        write_baseline(updated)
        print(f'Baseline: {len(baseline)} -> {len(updated)} files.')
        return 0
    errors = []
    for path, lines in sorted(sizes.items()):
        allowed = baseline.get(path, LIMIT)
        if lines > allowed:
            reason = 'grew past its baseline' if path in baseline else 'exceeds the limit'
            errors.append(f'{path}: {lines} lines {reason} ({allowed})')
    shrunk = [p for p, c in baseline.items() if sizes.get(p, 0) < c]
    for error in errors:
        print(error)
    if shrunk:
        print(f'{len(shrunk)} baseline file(s) shrank; run --update to lock that in.')
    if errors:
        print(f'{len(errors)} file-size violation(s); split the file (AGENTS.md).')
        return 1
    print(f'File sizes: {len(sizes)} files checked, {len(baseline)} over-limit files ratcheted.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
