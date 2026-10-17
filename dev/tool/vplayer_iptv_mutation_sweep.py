"""Generate explicit P15 mutation points and audit the old sweep attribution.

This tool never treats a whole-method replacement as coverage of descendants.
Outputs must live in the phase's git-common-dir evidence directory.
"""
import argparse
from collections import Counter
import fcntl
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--prior-evidence', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--guard-omissions', action='store_true',
                        help='Add separately identified whole-if omissions')
    args = parser.parse_args()
    package = args.parser_package.resolve()
    assert package.is_relative_to(ROOT / '.dart_tool/vplayer_parser')
    common = Path(subprocess.check_output(
        ['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'],
        cwd=ROOT, text=True).strip())
    evidence = common / 'refactor-evidence/vplayer/p15'
    output = args.output.resolve()
    assert output.is_relative_to(evidence)
    output.mkdir(parents=True, exist_ok=True)
    prior = args.prior_evidence.resolve()
    assert prior.is_relative_to(evidence)
    source = subprocess.check_output(
        ['git', 'show', '1d7699d2e:lib/screens/video_player_screen.dart'],
        cwd=ROOT, text=True)
    old_input = json.loads((prior / 'inventory-input.json').read_text())
    assert old_input['source'] == source
    input_path = output / 'inventory-input.json'
    input_path.write_text(json.dumps(old_input, indent=2) + '\n')
    adapter = ROOT / 'dev/tool/vplayer_iptv_mutation_points.dart.txt'
    kernel = output / 'mutation-points.dill'
    compile_command = ['nice', '-n', '19', 'dart', 'compile', 'kernel',
                       '--packages=' + str(package / '.dart_tool/package_config.json'),
                       '-o', str(kernel), str(adapter)]
    command = ['nice', '-n', '19', 'dart', str(kernel), str(input_path),
               str(output / 'points.json')]
    if args.guard_omissions:
        command.append('--guard-omissions')
    with (evidence / 'suite.lock').open('a') as lock:
        if os.environ.get('VP_SUITE_LOCK_HELD') != '1':
            fcntl.flock(lock, fcntl.LOCK_EX)
        env = dict(os.environ, VP_SUITE_LOCK_HELD='1')
        subprocess.run(compile_command, check=True, cwd=ROOT, env=env)
        subprocess.run(command, check=True, cwd=ROOT, env=env)
    inventory = json.loads((prior / 'inventory.json').read_text())
    history = json.loads((prior / 'mutation-table.json').read_text())
    # These declarations have no scalar literal/branch node for the Dart
    # visitor. Give their real initial-state/call expressions explicit points;
    # never fabricate a body kill and attribute it to their consumers.
    points = json.loads((output / 'points.json').read_text())
    # Adding whole-if faults must not renumber the existing explicit field
    # points. Guard IDs have their own namespace in the Dart visitor.
    extra_index = sum(not p['id'].startswith('g') for p in points) + 1
    raw_source = source.encode('utf-16-le')
    alternatives = {
        '_iptvCatchupRequests': 'IptvCatchupRequestGate()..begin()',
        '_iptvZapSourceId': "'wrong-source'",
        '_iptvZapCachedOriginCategory': "'wrong-origin'",
        '_iptvZapCachedPage': 'const VpIptvZapPage(channels: [], offset: 0, total: 0, sourceId: null, category: null, categories: [])',
        '_lastLiveChannelArmedUrl': "'wrong-url'",
        '_preferredIptvAudioLanguage': "'eng'",
        '_iptvArchiveRetryAt': 'DateTime.fromMillisecondsSinceEpoch(0)',
    }
    exclusions = []
    for member in inventory['members']:
        name = member['declaration']
        if name == '_adjacentIptvCategory':
            a, z = member['expression_offset'], member['expression_end']
            original = raw_source[a * 2:z * 2].decode('utf-16-le')
            after, kind = 'null', 'call-result-omission'
        elif name in alternatives:
            a, z = member['offset'], member['end']
            original = raw_source[a * 2:z * 2].decode('utf-16-le')
            if member.get('initializer_offset') is not None:
                begin = (member['initializer_offset'] - a) * 2
                end = (member['initializer_end'] - a) * 2
                text = original.encode('utf-16-le')
                after = (text[:begin] + alternatives[name].encode('utf-16-le') + text[end:]).decode('utf-16-le')
            else:
                assert original.endswith(';')
                after = original[:-1] + ' = ' + alternatives[name] + ';'
            kind = 'field-initial-state'
        elif member.get('field_type') == 'Timer?':
            exclusions.append({'declaration': name, 'line': member['line'],
                'reason': 'No initializer expression. Null is the only Timer? value constructible without creating/borrowing a resource. Inert construction is source-guarded; actual arm/cancel mutations belong to the owning methods, not a fabricated initializer kill.'})
            continue
        else:
            continue
        points.append({'id': 'x' + str(extra_index), 'declaration': name,
            'kind': kind, 'offset': a, 'end': z, 'line': member['line'],
            'text': original, 'after': after})
        extra_index += 1
    (output / 'points.json').write_text(json.dumps(points, indent=2) + '\n')
    (output / 'initializer-exclusions.json').write_text(json.dumps(exclusions, indent=2) + '\n')
    point_audit = []
    for point in inventory['points']:
        direct = [m for m in history if m['offset'] == point['offset']
                  and m['end'] == point['end']]
        point_audit.append(dict(point, exact_span_attempts=[{
            'run': m['group'] + '/' + m['id'],
            'operator': m['after'], 'status': m['result']['status'],
        } for m in direct]))
    by_declaration = []
    for member in inventory['members']:
        name = member['declaration']
        mutations = [m for m in history if m.get('declaration') == name]
        points = [p for p in point_audit if p['declaration'] == name]
        by_declaration.append({
            'declaration': name, 'line': member['line'],
            'ast_points': len(points),
            'old_killed_attempts': sum(m['result']['status'] == 'assertion-killed'
                                       for m in mutations),
            'old_exact_span_points_killed': sum(any(
                m['status'] == 'assertion-killed' for m in p['exact_span_attempts'])
                for p in points),
            'old_exact_span_points': [
                {'line': p['line'], 'kind': p['kind'], 'offset': p['offset'],
                 'end': p['end'], 'text': p['text'],
                 'attempts': p['exact_span_attempts']}
                for p in points if p['exact_span_attempts']],
        })
    report = {
        'original': '1d7699d2e',
        'old_operator_classes': [
            'whole method/getter body bypass',
            'retained caller no-op or expression replacement',
            'selected explicit guard/statement/constant changes',
            'compound body rewrites and fault insertions',
            'selected field initializer changes',
        ],
        'limitation': 'Exact span attribution is conservative; enclosing body '
                      'kills do not imply a nested AST point was tested. '
                      'No claim that 221 kills cover 1521 points survives.',
        'old_points': point_audit,
        'declarations': by_declaration,
        'new_policy': dict(Counter(p['kind'] for p in json.loads(
            (output / 'points.json').read_text()))),
        'generation_command': command,
    }
    (output / 'prior-sweep-audit.json').write_text(
        json.dumps(report, indent=2) + '\n')
    print(json.dumps(report['new_policy'], indent=2))


if __name__ == '__main__':
    main()
