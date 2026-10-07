#!/usr/bin/env python3
"""Clean Android JVM runs and identity comparisons (tv-player plan, rule 6)."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

JBR = Path('/Applications/Android Studio.app/Contents/jbr/Contents/Home')


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args]).decode().strip()


def evidence_root(root):
    return Path(git(root, 'rev-parse', '--path-format=absolute', '--git-common-dir')) / 'refactor-evidence/tvplayer'


def fingerprint(root):
    digest = hashlib.sha256()
    names = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z', '--cached', '--others', '--exclude-standard'])
    for name in sorted(set(names.split(b'\0')) - {b''}):
        path = root / os.fsdecode(name)
        digest.update(name + b'\0')
        digest.update(path.read_bytes() if path.is_file() else b'<missing>')
    digest.update(git(root, 'rev-parse', 'HEAD').encode())
    digest.update(git(root, 'status', '--porcelain').encode())
    return digest.hexdigest()


def identities(xml_dir):
    tests = {}
    paths = sorted(xml_dir.glob('*.xml'))
    if not paths:
        raise ValueError('no XML')
    for path in paths:
        suite = ET.parse(path).getroot()
        cases = list(suite.iter('testcase'))
        if len(cases) != int(suite.get('tests', len(cases))):
            raise ValueError('partial XML: ' + path.name)
        for case in cases:
            key = case.attrib['classname'] + '::' + case.attrib['name']
            if key in tests:
                raise ValueError('duplicate test identity: ' + key)
            statuses = [c.tag for c in case if c.tag in ('failure', 'error', 'skipped')]
            tests[key] = statuses[0] if statuses else 'pass'
    if not tests:
        raise ValueError('no identities')
    return tests


def compare(current, baseline):
    errors = []
    meta, tests = current['meta'], current['tests']
    old = baseline['tests']
    if not tests or meta.get('count') != len(tests):
        errors.append('no/partial XML')
    if meta.get('archive_error'):
        errors.append(meta['archive_error'])
    if meta.get('tree_changed'):
        errors.append('tree changed during run')
    if meta.get('aborted'):
        errors.append('Gradle aborted before a complete test run')
    # Compatibility with the reference archive: a nonzero exit with failures
    # is expected. New archives also positively record test-task completion.
    if meta.get('gradle_exit') and not any(s in ('failure', 'error') for s in tests.values()):
        errors.append('Gradle failed without test failures')
    for key in sorted(old.keys() - tests.keys()):
        errors.append('missing identity: ' + key)
    for key, status in sorted(tests.items()):
        if status in ('failure', 'error') and old.get(key) != status:
            errors.append('new ' + status + ': ' + key)
        if status == 'skipped' and old.get(key) != 'skipped':
            errors.append('new skip: ' + key)
        if status not in ('pass', 'failure', 'error', 'skipped'):
            errors.append('unknown status: ' + key)
    return errors


def run(root, label):
    if not label or Path(label).name != label or label in ('.', '..'):
        raise ValueError('label must be one directory name')
    archive = evidence_root(root) / 'junit' / label
    if archive.exists():
        raise ValueError('archive already exists (choose a new label): ' + str(archive))
    archive.mkdir(parents=True)
    before = fingerprint(root)
    revision = git(root, 'rev-parse', 'HEAD')
    dirty = len(git(root, 'status', '--porcelain').splitlines())
    xml = root / 'build/app/test-results/testDebugUnitTest'
    shutil.rmtree(xml, ignore_errors=True)
    env = dict(os.environ, JAVA_HOME=str(JBR))
    with (archive / 'gradle.log').open('w') as log:
        result = subprocess.run(['./gradlew', ':app:cleanTestDebugUnitTest', ':app:testDebugUnitTest', '--console=plain'],
                                cwd=root / 'android', env=env, stdout=log, stderr=subprocess.STDOUT)
    after = fingerprint(root)
    tests, archive_error = {}, None
    if xml.exists():
        shutil.copytree(xml, archive / 'xml')
    try:
        tests = identities(archive / 'xml')
    except (ValueError, ET.ParseError, KeyError) as error:
        archive_error = str(error)
    log = (archive / 'gradle.log').read_text()
    task_seen = '> Task :app:testDebugUnitTest' in log
    test_failure = "Execution failed for task ':app:testDebugUnitTest'." in log and 'There were failing tests.' in log
    aborted = not task_seen or (result.returncode != 0 and not test_failure)
    java = subprocess.run([str(JBR / 'bin/java'), '-version'], capture_output=True, text=True, check=True).stderr.splitlines()[0]
    meta = dict(revision=revision, dirty_files=dirty, gradle_exit=result.returncode, java=java,
                count=len(tests), by_status={s: list(tests.values()).count(s) for s in sorted(set(tests.values()))},
                tree_before=before, tree_after=after, tree_changed=before != after, aborted=aborted)
    if archive_error:
        meta['archive_error'] = archive_error
    report = dict(meta=meta, tests=tests)
    (archive / 'identities.json').write_text(json.dumps(report, indent=1, sort_keys=True) + '\n')
    print(json.dumps(meta, sort_keys=True))
    print(archive)
    return 2 if archive_error or aborted or before != after else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--worktree', type=Path, default=Path(__file__).resolve().parents[2])
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('run').add_argument('label')
    check = commands.add_parser('compare')
    check.add_argument('label')
    check.add_argument('--against', required=True)
    args = parser.parse_args()
    if args.command == 'run':
        return run(args.worktree, args.label)
    folder = evidence_root(args.worktree) / 'junit'
    errors = compare(json.loads((folder / args.label / 'identities.json').read_text()),
                     json.loads((folder / args.against / 'identities.json').read_text()))
    for error in errors:
        print(error)
    if not errors:
        print('PASS: all baseline identities retained; no new failures or skips')
    return bool(errors)


if __name__ == '__main__':
    sys.exit(main())
