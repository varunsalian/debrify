#!/usr/bin/env python3
"""Fail on analyzer warnings/errors in migrated code unless they are recorded.

Moving legacy code into the CI-analyzed scope can expose warnings that already
existed in the original file. A move-only refactor keeps that code verbatim, so
each such warning is recorded in `analyzer_allowlist.txt` with the original
location it came from. Anything else fails:

  * any error;
  * any warning not in the allowlist (matched by severity, rule, file and
    message, not line, so moves within a file don't churn it);
  * any allowlist entry that no longer matches (stale entries can't hide a
    later regression).

Usage: flutter analyze --no-fatal-infos --no-fatal-warnings <paths> | tee out
       python3 dev/tool/check_analyzer_allowlist.py out
"""
import re
import sys
from pathlib import Path

ALLOWLIST = Path(__file__).with_name('analyzer_allowlist.txt')
LINE = re.compile(r'^\s*(error|warning|info) • (.*) • (\S+?):\d+:\d+ • (\S+)\s*$')


def load_allowlist():
    entries = []
    for raw in ALLOWLIST.read_text().splitlines():
        if not raw.strip() or raw.startswith('#'):
            continue
        severity, rule, path, message = raw.split(' | ', 3)
        entries.append((severity, rule, path, message))
    return entries


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    allowed = load_allowlist()
    seen = set()
    failures = []
    for line in Path(argv[1]).read_text().splitlines():
        match = LINE.match(line)
        if not match:
            continue
        severity, message, path, rule = match.groups()
        if severity == 'info':
            continue
        key = (severity, rule, path, message)
        if severity == 'warning' and key in allowed:
            seen.add(key)
            continue
        failures.append(line.strip())
    stale = [' | '.join(e) for e in allowed if e not in seen]
    for line in failures:
        print('NOT ALLOWED: ' + line)
    for entry in stale:
        print('STALE ALLOWLIST ENTRY: ' + entry)
    if failures or stale:
        return 1
    print(f'analyzer allowlist: {len(seen)} recorded pre-existing warning(s), nothing new')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
