"""Run small, serial batches of original-library IPTV mutants in isolated test files.

All generated source, test mirrors, patches and logs live in the P15 evidence
checkout. Each library differs from the original by exactly its recorded fault.
Generated test imports, group-name normalization, the fixed common-dir lookup
and test-runner metadata are adapted; application fault spans stay exact.
Each mutant gets its own serial test isolate. No private State injection,
production seam or fixture expectation is changed.
Controls execute every selected case. Mutation isolates stop executing bodies
after their first failure; later cases remain loaded and are explicitly skipped.
Only an assertion failure earns kill credit, never a skip or timeout.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
SCREEN = 'lib/screens/video_player_screen.dart'
SCREEN_URI = 'package:debrify/screens/video_player_screen.dart'
TEST_API = """import 'package:flutter_test/flutter_test.dart' as ft;
import 'package:test_api/src/backend/invoker.dart';
import 'package:test_api/src/backend/state.dart' as test_state;
export 'package:flutter_test/flutter_test.dart' hide testWidgets;
dynamic previous;
const stopAfterFailure = STOP_AFTER_FAILURE;
void testWidgets(String description, ft.WidgetTesterCallback callback, {
  bool? skip, ft.Timeout? timeout, bool semanticsEnabled = true,
  ft.TestVariant<Object?> variant = const ft.DefaultTestVariant(),
  dynamic tags, int? retry, dynamic experimentalLeakTesting,
}) {
  ft.testWidgets(description, (tester) async {
    if (stopAfterFailure && previous != null &&
        previous.state.result != test_state.Result.success) {
      ft.markTestSkipped('An earlier case already failed in this mutant isolate');
      return;
    }
    previous = Invoker.current!.liveTest;
    print('P15_MUTANT_BODY_STARTED');
    await callback(tester);
  }, skip: skip, timeout: timeout, semanticsEnabled: semanticsEnabled,
     variant: variant, tags: tags, retry: retry,
     experimentalLeakTesting: experimentalLeakTesting);
}
"""


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--batch-size', type=int, default=6, choices=range(1, 9))
    parser.add_argument('--control', action='store_true')
    args = parser.parse_args()
    common = Path(subprocess.check_output(
        ['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'],
        cwd=ROOT, text=True).strip())
    evidence = common / 'refactor-evidence/vplayer/p15'
    output = args.output.resolve()
    assert output.is_relative_to(evidence)
    output.mkdir(parents=True, exist_ok=True)
    checkout = evidence / 'original'
    original = subprocess.check_output(
        ['git', 'show', '1d7699d2e:' + SCREEN], cwd=ROOT)
    encoded = original.decode().encode('utf-16-le')
    assert subprocess.run(
        ['git', 'symbolic-ref', '-q', 'HEAD'], cwd=checkout,
        capture_output=True).returncode == 1
    plan = json.loads(args.plan.read_text())
    assert len({p['id'] for p in plan}) == len(plan)
    receipt = output / 'results.json'
    results = json.loads(receipt.read_text()) if receipt.exists() else []
    done = {r['id'] for r in results if r.get('complete')}
    fixture = 'test/features/video_player/support/fixtures/iptv_original_outputs.json'
    expected = json.loads((ROOT / fixture).read_text())
    source_hashes = {
        str(p.relative_to(ROOT)): digest(p.read_bytes())
        for p in (ROOT / 'test/features/video_player').rglob('*.dart')
        if 'p15_batch' not in str(p)
    }
    source_hashes[fixture] = digest((ROOT / fixture).read_bytes())
    input_text = json.dumps({
        'original': '1d7699d2e', 'original_sha256': digest(original),
        'plan_sha256': digest(args.plan.read_bytes()),
        'batch_size': args.batch_size, 'control': args.control,
        'runner_sha256': digest(Path(__file__).read_bytes()),
        'widget_timeout_seconds': 30,
        'test_registration_adapter': TEST_API.replace(
            'STOP_AFTER_FAILURE', 'false' if args.control else 'true'),
        'hashes': source_hashes, 'expected_case_hashes': {
            k: digest(json.dumps(v, sort_keys=True).encode())
            for k, v in expected.items()},
    }, indent=2) + '\n'
    input_name = 'inputs-' + digest(input_text.encode())[:16] + '.json'
    (output / input_name).write_text(input_text)
    (output / 'inputs.json').write_text(input_text)
    env = dict(os.environ, VPLAYER_EVIDENCE_ROOT=str(evidence),
               VP_SUITE_LOCK_HELD='1',
               PATH=str(evidence / 'bin') + os.pathsep + os.environ['PATH'])
    counter = 0
    with (evidence / 'suite.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        assert (checkout / SCREEN).read_bytes() == original
        # No other application source or dependency may differ from the base.
        assert not subprocess.check_output(['git', 'diff', '1d7699d2e', '--',
            'lib', 'packages', 'pubspec.yaml', 'pubspec.lock',
            'analysis_options.yaml'], cwd=checkout)
        mirror = checkout / 'test/features/video_player/p15_batch'
        generated = []

        def record(point, status, log, **extra):
            nonlocal results
            row = dict(id=point['id'], declaration=point.get('declaration'),
                       status=status, complete=True, log=str(log),
                       input_receipt=input_name, **extra)
            results = [r for r in results if r['id'] != point['id']] + [row]
            temporary = receipt.with_suffix('.tmp')
            temporary.write_text(json.dumps(results, indent=2) + '\n')
            temporary.replace(receipt)
            print(point['id'], status, flush=True)

        def run_batch(points):
            nonlocal counter
            counter += 1
            label = f'batch-{counter:04d}-{points[0]["id"]}'
            log = output / (label + '.jsonl')
            shutil.rmtree(mirror, ignore_errors=True)
            mirror.mkdir(parents=True)
            drivers, selectors = [], []
            mappings = []
            for index, point in enumerate(points):
                identifier = point['id']
                assert re.fullmatch(r'[A-Za-z0-9_]+', identifier)
                assert encoded[point['offset'] * 2:point['end'] * 2].decode(
                    'utf-16-le') == point['text']
                variant = original if args.control else (
                    encoded[:point['offset'] * 2]
                    + point['after'].encode('utf-16-le')
                    + encoded[point['end'] * 2:]).decode('utf-16-le').encode()
                if args.control:
                    target = checkout / SCREEN
                    variant_uri = SCREEN_URI
                else:
                    target = checkout / f'lib/screens/p15_mutation_{identifier}.dart'
                    target.write_bytes(variant)
                    generated.append(target)
                    variant_uri = 'package:debrify/screens/' + target.name
                base = mirror / identifier
                test_api = base / 'mutation_test_api.dart'
                test_api.parent.mkdir(parents=True, exist_ok=True)
                test_api.write_text(TEST_API.replace(
                    'STOP_AFTER_FAILURE', 'false' if args.control else 'true'))
                mappings.append(dict(id=identifier, variant_sha256=digest(variant),
                                     source=str(target), fault=point))
                # Mirror one coherent test library graph, preserving external
                # fixture imports by their absolute original URI. Only copy
                # selected suites and their transitive fixture imports, avoiding
                # repeated writes of unrelated test libraries for every fault.
                local = ROOT / 'test/features/video_player'
                graph, pending_files = set(), [ROOT / f for f in point['files']]
                while pending_files:
                    path = pending_files.pop().resolve()
                    if path in graph:
                        continue
                    assert path.is_relative_to(local)
                    graph.add(path)
                    for match in re.finditer(
                        r"(?:import|export)\s+(['\"])([^'\"]+)\1",
                        path.read_text(),
                    ):
                        uri = match.group(2)
                        if ':' not in uri and not uri.startswith('/'):
                            dependency = (path.parent / uri).resolve()
                            if dependency.is_relative_to(local):
                                pending_files.append(dependency)
                for path in sorted(graph):
                    relative = path.relative_to(ROOT / 'test/features/video_player')
                    destination = base / relative
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    text = path.read_text().replace(SCREEN_URI, variant_uri)
                    text = text.replace('package:flutter_test/flutter_test.dart',
                                        test_api.as_uri())

                    def rewrite(match):
                        directive, quote, uri = match.groups()
                        if ':' in uri or uri.startswith('/'):
                            return match.group(0)
                        resolved = (path.parent / uri).resolve()
                        local = ROOT / 'test/features/video_player'
                        adapted = (base / resolved.relative_to(local)).as_uri() if (
                            resolved.is_relative_to(local)) else (
                                checkout / resolved.relative_to(ROOT)).as_uri()
                        return directive + quote + adapted + quote

                    text = re.sub(r"((?:import|export)\s+)(['\"])([^'\"]+)\2",
                                  rewrite, text)
                    if path.name == 'video_player_environment.dart':
                        # E is explicit for every run. The common-dir lookup is
                        # otherwise unused; freeze its identical result instead
                        # of spawning one git process for every generated case.
                        text, count = re.subn(
                            r"final common = Process\.runSync\('git', \[.*?\]\)\.stdout\.toString\(\)\.trim\(\);",
                            'final common = ' + json.dumps(str(common)) + ';',
                            text, count=1, flags=re.S)
                        assert count == 1
                    if path.name == 'iptv_output_observation.dart':
                        text = text.replace('Invoker.current!.liveTest.test.name',
                            "Invoker.current!.liveTest.test.name.replaceFirst("
                            "RegExp(r'^P15M_[A-Za-z0-9_]+ '), '')")
                    destination.write_text(text)
                imports, registrations = [], []
                for number, file in enumerate(point['files']):
                    relative = Path(file).relative_to('test/features/video_player')
                    alias = f'm{index}_{number}'
                    imports.append(f"import '{identifier}/{relative}' as {alias};")
                    registrations.append(
                        f"group('P15M_{identifier}', () {{ {alias}.main(); }});")
                driver = mirror / f'candidate_{identifier}_test.dart'
                driver.write_text("import 'package:flutter_test/flutter_test.dart';\n"
                    + '\n'.join(imports) + '\nvoid main() {\n'
                    + 'final binding = TestWidgetsFlutterBinding.ensureInitialized();\n'
                    + 'if (binding is AutomatedTestWidgetsFlutterBinding) {\n'
                    + 'binding.defaultTestTimeout = const Timeout(Duration(seconds: 30));\n}\n'
                    + '\n'.join(registrations) + '\n}\n')
                drivers.append(str(driver))
                regex = point.get('regex')
                selectors.append('^P15M_' + identifier + ' ' + (
                    '.*' if not regex else '.*(?:' + regex.removeprefix('^').removesuffix('$') + ').*') + '$')
            cmd = ['nice', '-n', '19', 'flutter', 'test', '--no-pub',
                   '--dart-define=DEBRIFY_VP_TEST_HOOKS=true', '--concurrency=1',
                   '--timeout=30s', '--reporter=json', '--name',
                   '|'.join(selectors), *drivers]
            (output / (label + '.mapping.json')).write_text(json.dumps(
                mappings, indent=2) + '\n')
            started = time.monotonic()
            with log.open('w') as out, (output / (label + '.stderr')).open('w') as err:
                process = subprocess.Popen(cmd, cwd=checkout, env=env,
                    stdout=out, stderr=err, start_new_session=True)
                try:
                    # A synchronous mutant can starve the test timeout. Bound
                    # the whole batch as well; minute-long clock cases opt in
                    # through their selected file rather than every candidate.
                    clock_cases = sum(any('archive_retry' in f or
                                          'recovery_lifetime' in f
                                          for f in p['files'])
                                      for p in points)
                    stall_cases = sum(any('archive_stall' in f for f in p['files'])
                                      for p in points)
                    code = process.wait(
                        timeout=45 * len(points) + 90 * clock_cases + 35 * stall_cases)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                    code = 124
            events = []
            for line in log.read_text().splitlines():
                try:
                    events.append(json.loads(line))
                except ValueError:
                    pass
            complete = any(e.get('type') == 'done' for e in events)
            names = {e['test']['id']: e['test']['name'] for e in events
                     if e.get('type') == 'testStart'}
            compile_error = any(e.get('type') == 'error' and (
                'Compilation failed' in e.get('error', '') or
                'Failed to load' in e.get('error', '')) for e in events)
            details = dict(command=cmd, exit=code,
                           seconds=round(time.monotonic() - started, 2))
            compiler_text = log.read_text() + (output / (label + '.stderr')).read_text()
            invalid_ids = set(re.findall(
                r'p15_mutation_([A-Za-z0-9_]+)\.dart:\d+:\d+: Error:', compiler_text)) if compile_error else set()
            assertions = {e['testID'] for e in events if e.get('type') == 'print'
                          and 'Expected:' in e.get('message', '')}
            assertions.update(e['testID'] for e in events if e.get('type') == 'error'
                              and e.get('isFailure') is True
                              and 'Expected:' in e.get('error', ''))
            fixture_setup = {e['testID'] for e in events
                if e.get('type') in ['print', 'error'] and any(
                    frame in e.get('message', e.get('error', ''))
                    for frame in ['PipLifecycleDriver.initialize',
                                  'IptvWorkflowDriver.initialize',
                                  'VideoPlayerEnvironment.initialize'])}
            assertions.difference_update(fixture_setup)
            first_failure = {}
            body_started = set()
            for event in events:
                test_id = event.get('testID')
                message = event.get('message', event.get('error', ''))
                if event.get('type') == 'print' and message == 'P15_MUTANT_BODY_STARTED':
                    body_started.add(test_id)
                if event.get('type') == 'error' or (
                    event.get('type') == 'print' and (
                        'Expected:' in message or 'EXCEPTION CAUGHT BY' in message)
                ):
                    first_failure.setdefault(test_id,
                        'assertion' if 'Expected:' in message else 'runtime')
            assertions = {i for i in assertions
                          if i in body_started and first_failure.get(i) == 'assertion'}
            for point in points:
                if point['id'] in invalid_ids:
                    record(point, 'invalid-candidate', log, **details)
                    continue
                prefix = 'P15M_' + point['id'] + ' '
                observed = {i: n for i, n in names.items() if n.startswith(prefix)}
                actual_cases = {n.removeprefix(prefix) for n in observed.values()}
                expected_cases = point.get('expected_cases')
                selected_all = (expected_cases is None or
                                actual_cases == set(expected_cases))
                finished = [e for e in events if e.get('type') == 'testDone'
                            and e['testID'] in observed]
                failed = {e['testID'] for e in finished if e['result'] != 'success'}
                kills = [observed[i] for i in sorted(assertions & failed)]
                # After a runtime failure, framework cleanup/setup assertions
                # in later cases must never turn that candidate into a kill.
                if not args.control and failed:
                    first_failed = next(e['testID'] for e in finished
                                        if e['testID'] in failed)
                    kills = [observed[first_failed]] if first_failed in assertions else []
                point_complete = (expected_cases is not None and selected_all
                    and len(finished) == len(observed)
                    and {e['testID'] for e in finished} == set(observed))
                status = ('invalid-selector' if not observed or not selected_all else
                    'assertion-killed' if (complete or point_complete) and kills else
                    'survived' if (complete or point_complete) and len(finished) == len(observed)
                    and not failed else 'uncredited-runtime-or-timeout')
                record(point, status, log, assertion_tests=kills,
                       point_complete=point_complete,
                       skipped_tests=[observed[e['testID']] for e in finished
                                      if e.get('skipped')],
                       body_started_tests=[observed[i] for i in sorted(body_started & set(observed))],
                       first_failure_types={observed[i]: first_failure[i]
                                            for i in observed if i in first_failure},
                       uncredited_fixture_setup=[observed[i] for i in
                           sorted(fixture_setup & set(observed))],
                       tests=[observed[e['testID']] for e in finished], **details)

        try:
            pending = [p for p in plan if p['id'] not in done]
            for start in range(0, len(pending), args.batch_size):
                run_batch(pending[start:start + args.batch_size])
                for path in generated:
                    path.unlink(missing_ok=True)
                generated.clear()
                # Bound compiler restarts and leave the OS time between batches.
                time.sleep(3)
                if (output.parent / 'PAUSE-BATCHES').exists():
                    break
        finally:
            for path in generated:
                path.unlink(missing_ok=True)
            shutil.rmtree(mirror, ignore_errors=True)
            assert (checkout / SCREEN).read_bytes() == original
    print('Archived', len(results), 'results', flush=True)


if __name__ == '__main__':
    main()
