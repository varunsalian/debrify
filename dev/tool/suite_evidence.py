#!/usr/bin/env python3
"""Record and compare test-suite evidence by test identity (suite::name).

  run NAME [PATHS...]          flutter test --reporter json (whole suite or
                               PATHS) -> <evidence>/NAME.jsonl, plus
                               NAME.env.json (Flutter SDK, HEAD, tested tree, paths)
  compare [--against FILE] [--moved | --relocate FROM=TO_PREFIX ...] RUN...
                               .jsonl runs: no new failures, missing tests or
                               newly skipped tests versus FILE. .txt files:
                               `flutter analyze` output, no added diagnostics
                               (by file, rule and message; with --moved, by
                               rule and message only, for move-only batches
                               whose diagnostics change file). --relocate is
                               stricter: a diagnostic may change file only
                               from FROM to a file under TO_PREFIX, with the
                               same severity, rule and message; everything
                               else is compared by file. Repeatable.
  check KNOWN PATHS...         CI: run PATHS (`@file` = one path per line); fail on any failure not listed in
                               KNOWN (one suite::name per line) and on any
                               listed identity that no longer exists.

<evidence> is `refactor-evidence/` in the git common directory, so every
worktree of a clone shares it; it is never committed. A fresh clone has no
evidence: record a baseline at the plan's base revision first. Comparisons are
only valid between runs with the same Flutter SDK, which `run` records and
`compare` checks when both runs have an env file. `run` also records the
checkout root, so runs from different worktrees compare by the same
repository-relative identities.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def evidence_dir() -> Path:
    common = subprocess.run(
        ['git', 'rev-parse', '--git-common-dir'],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout.strip()
    return (ROOT / common).resolve() / 'refactor-evidence'


def run_root(path) -> str:
    # Suite paths are absolute; strip the root of the checkout that recorded
    # the run (another worktree, another machine), not this one.
    env = Path(path).with_suffix('.env.json')
    if env.exists():
        recorded = json.loads(env.read_text()).get('root')
        if recorded:
            return recorded
    return str(ROOT)


def outcomes(path):
    root = run_root(path)
    tests, suites, results, done = {}, {}, {}, False
    for line in Path(path).read_text().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if not isinstance(event, dict):
            continue
        kind = event.get('type')
        if kind == 'suite':
            suites[event['suite']['id']] = event['suite']['path'].replace(root + '/', '')
        elif kind == 'testStart':
            tests[event['test']['id']] = event['test']
        elif kind == 'done':
            done = True
        elif kind == 'testDone' and not event.get('hidden', False):
            test = tests[event['testID']]
            identity = suites[test['suiteID']] + '::' + test['name']
            results[identity] = 'skipped' if event.get('skipped') else event['result']
    assert done and results, f'Runner incomplete (no done event/outcomes): {path}'
    return results, set(suites.values())


def diagnostics(path):
    found = Counter()
    for line in Path(path).read_text().splitlines():
        parts = [v.strip() for v in line.split(' • ')]
        if len(parts) == 4:
            location = re.sub(r':\d+:\d+$', '', parts[2])
            found[(parts[0], location, parts[3], parts[1])] += 1
    assert found, f'No analyzer diagnostics parsed: {path}'
    return found


def without_location(found):
    merged = Counter()
    for (severity, _, message, rule), count in found.items():
        merged[(severity, message, rule)] += count
    return merged


def relocate(added, removed, source, prefix):
    # Pair each added diagnostic under `prefix` with a removed one from
    # `source` that has the same severity, message and rule.
    added, removed = Counter(added), Counter(removed)
    for (severity, location, message, rule), count in list(added.items()):
        if not location.startswith(prefix):
            continue
        origin = (severity, source, message, rule)
        paired = min(count, removed.get(origin, 0))
        if paired:
            added[(severity, location, message, rule)] -= paired
            removed[origin] -= paired
    return +added, +removed


def git_tree_evidence():
    """Identify tracked input without changing the index or the stash list."""
    def git(*args):
        return subprocess.run(['git', *args], cwd=ROOT, capture_output=True,
                              text=True, check=True).stdout.strip()
    head = git('rev-parse', 'HEAD')
    snapshot = git('stash', 'create')
    return {
        'head': head,
        'index_tree': git('write-tree'),
        'worktree_snapshot': snapshot or None,
        'tested_tree': git('rev-parse', (snapshot or head) + '^{tree}'),
        'untracked_paths': git('ls-files', '--others', '--exclude-standard').splitlines(),
    }


def flutter_env(paths):
    version = subprocess.run(
        ['flutter', '--version', '--machine'], cwd=ROOT, capture_output=True, text=True,
    ).stdout
    try:
        sdk = json.loads(version[version.index('{'):])
        sdk = {k: sdk.get(k) for k in ('frameworkVersion', 'frameworkRevision', 'dartSdkVersion')}
    except ValueError:
        sdk = {'raw': version.strip()}
    return {'sdk': sdk, **git_tree_evidence(), 'root': str(ROOT), 'paths': list(paths)}


def flutter_test_json(paths, out: Path) -> int:
    with out.open('w') as stdout, out.with_suffix('.stderr').open('w') as stderr:
        return subprocess.run(
            ['flutter', 'test', '--reporter', 'json', *paths],
            cwd=ROOT, stdout=stdout, stderr=stderr,
        ).returncode


def cmd_run(name, paths):
    prefix = evidence_dir() / name
    prefix.parent.mkdir(parents=True, exist_ok=True)
    out = prefix.with_suffix('.jsonl')
    env = flutter_env(paths)
    env_path = prefix.with_suffix('.env.json')
    env_path.write_text(json.dumps(env, indent=2))
    code = flutter_test_json(paths, out)
    end = git_tree_evidence()
    env['end_head'] = end['head']
    env['end_tree'] = end['tested_tree']
    env['tree_changed_during_run'] = (env['tested_tree'] != end['tested_tree']
                                      or env['head'] != end['head']
                                      or env['untracked_paths'] != end['untracked_paths'])
    env_path.write_text(json.dumps(env, indent=2))
    results, _ = outcomes(out)
    print(f'{out}: exit {code}, {dict(Counter(results.values()))}')
    print('The verdict is `compare`, not this exit code.')
    return 0


def env_for(path: Path):
    env = path.with_suffix('.env.json')
    return json.loads(env.read_text()) if env.exists() else None


def cmd_compare(args):
    against = None
    if '--against' in args:
        i = args.index('--against')
        against = Path(args[i + 1])
        del args[i:i + 2]
    moved = '--moved' in args
    if moved:
        args.remove('--moved')
    relocations = []
    while '--relocate' in args:
        i = args.index('--relocate')
        spec = args[i + 1] if i + 1 < len(args) else ''
        source, sep, prefix = spec.partition('=')
        if not sep or not source.strip() or not prefix.strip():
            print(f'--relocate needs FROM=TO_PREFIX with both parts, got {spec!r}')
            return 2
        relocations.append((source, prefix))
        del args[i:i + 2]
    if moved and relocations:
        print('--moved and --relocate cannot be combined')
        return 2
    if against is None:
        print('compare needs --against <baseline>')
        return 2
    ok = True
    for arg in args:
        run = Path(arg)
        if run.suffix == '.jsonl':
            before_env, after_env = env_for(against), env_for(run)
            if any(env and env.get('tree_changed_during_run')
                   for env in (before_env, after_env)):
                print('Tested tree changed during run; comparison invalid:', run.name)
                ok = False
                continue
            if before_env and after_env and before_env['sdk'] != after_env['sdk']:
                print('SDK differs; comparison invalid:', before_env['sdk'], after_env['sdk'])
                ok = False
                continue
            before = (json.loads(against.read_text()) if against.suffix == '.json'
                      else outcomes(against)[0])
            after, suites = outcomes(run)
            scoped = after_env and after_env.get('paths')
            if scoped:
                # A scoped run only answers for the suites it ran.
                before = {k: v for k, v in before.items() if k.split('::')[0] in suites}
            new_failures = {k: v for k, v in after.items()
                            if v not in ('success', 'skipped')
                            and before.get(k) not in ('failure', 'error')}
            missing = sorted(k for k in before if k not in after)
            missing_suites = sorted({k.split('::')[0] for k in missing} - suites)
            newly_skipped = sorted(k for k, v in after.items()
                                   if v == 'skipped' and before.get(k) == 'success')
            fixed = sorted(k for k, v in after.items()
                           if v == 'success' and before.get(k) in ('failure', 'error'))
            added = sorted(k for k in after if k not in before)
            print(run.name, 'vs', against.name, dict(Counter(after.values())))
            print('new failures', new_failures)
            print('missing tests', len(missing), '(absent suites:', missing_suites, ')')
            for k in missing:
                print('  missing:', k)
            print('newly skipped', newly_skipped)
            print('fixed', fixed, 'added identities', len(added))
            ok = ok and not new_failures and not missing and not newly_skipped
        else:
            after, before = diagnostics(run), diagnostics(against)
            if moved:
                after, before = without_location(after), without_location(before)
            added, removed = after - before, before - after
            for source, prefix in relocations:
                added, removed = relocate(added, removed, source, prefix)
            print(run.name, 'added', list(added.elements()), 'removed', list(removed.elements()))
            ok = ok and not added
    print('PASS' if ok else 'FAIL')
    return 0 if ok else 1


def expand(paths):
    # `@file` reads one test path per line (comments and blanks skipped).
    out = []
    for path in paths:
        if path.startswith('@'):
            out += [line.strip() for line in (ROOT / path[1:]).read_text().splitlines()
                    if line.strip() and not line.startswith('#')]
        else:
            out.append(path)
    return out


def failure_details(path, identities):
    """Expose runner errors for unexpected identities without changing verdicts."""
    suites, tests = {}, {}
    for line in Path(path).read_text().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if not isinstance(event, dict):
            continue
        if event.get('type') == 'suite':
            suites[event['suite']['id']] = event['suite']['path'].replace(str(ROOT) + '/', '')
        elif event.get('type') == 'testStart':
            test = event['test']
            tests[test['id']] = suites[test['suiteID']] + '::' + test['name']
        elif event.get('type') == 'error' and tests.get(event['testID']) in identities:
            print('RUNNER ERROR:', tests[event['testID']])
            print(event.get('error', ''))
            print(event.get('stackTrace', ''))


def cmd_check(known_file, paths):
    paths = expand(paths)
    known = {line.strip() for line in Path(known_file).read_text().splitlines()
             if line.strip() and not line.startswith('#')}
    # A per-run file: parallel worktrees running `check` at the same time
    # must not overwrite each other's results.
    fd, name = tempfile.mkstemp(prefix='suite_evidence_check-', suffix='.jsonl',
                                dir='/tmp' if Path('/tmp').is_dir() else '.')
    os.close(fd)
    out = Path(name)
    flutter_test_json(paths, out)
    results, _ = outcomes(out)
    failing = {k for k, v in results.items() if v not in ('success', 'skipped')}
    unexpected = sorted(failing - known)
    stale = sorted(k for k in known if k not in results)
    fixed = sorted(k for k in known if results.get(k) == 'success')
    print(dict(Counter(results.values())))
    for k in unexpected:
        print('UNEXPECTED FAILURE:', k)
    if unexpected:
        failure_details(out, set(unexpected))
    for k in stale:
        print('KNOWN FAILURE NO LONGER EXISTS (update the list):', k)
    for k in fixed:
        print('known failure now passes (remove it from the list):', k)
    return 1 if unexpected or stale or fixed else 0


def main(argv):
    if len(argv) >= 2 and argv[0] == 'run':
        return cmd_run(argv[1], expand(argv[2:]))
    if argv and argv[0] == 'compare':
        return cmd_compare(argv[1:])
    if len(argv) >= 3 and argv[0] == 'check':
        return cmd_check(argv[1], argv[2:])
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
