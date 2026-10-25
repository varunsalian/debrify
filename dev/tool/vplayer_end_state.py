#!/usr/bin/env python3
"""Video-player facade end-state declaration guard (Phase 21b).

Parser-based. Freezes the facade's declaration set in vplayer_end_state.json:
its top-level declarations (name and kind), the members of
`_VideoPlayerScreenState` and the adapter classes. The current set must equal
the frozen set exactly, so adding a member fails and removing one requires
removing it from the frozen list (shrink-only at declaration level; growth only
through the reviewed raise procedure in video-player-screen-plan.md, which
changes the facade, the exact cap, the baseline line and this list together).
New behaviour lands in a collaborator.
"""
import argparse
import json
from pathlib import Path

from check_verbatim_moves import ROOT, parse, ensure_parser_package

FACADE = 'lib/screens/video_player_screen.dart'
FROZEN = 'dev/tool/vplayer_end_state.json'
STATE = '_VideoPlayerScreenState'


def declaration_set(text, package):
    unit = parse({FACADE: text}, package)[FACADE]
    top = [dict(name=d['name'], kind=d['kind'].removesuffix('Impl')) for d in unit['declarations']]
    state = next((d for d in unit['declarations'] if d['name'] == STATE), None)
    members = [m['name'] + ('@set' if m.get('isSetter') else '') for m in (state or {}).get('members', [])]
    adapters = [d['name'] for d in unit['declarations']
                if d['name'].startswith('_Vp') and d['name'].endswith('HostAdapter')]
    return dict(top_level=top, state_members=members, adapters=adapters)


def compare(current, frozen):
    errors = []
    for part in ('top_level', 'state_members', 'adapters'):
        now = [json.dumps(x, sort_keys=True) for x in current[part]]
        then = [json.dumps(x, sort_keys=True) for x in frozen[part]]
        errors += [f'{part}: declaration added: {x}' for x in now if x not in then]
        errors += [f'{part}: declaration removed (update {FROZEN} in the same reviewed commit): {x}'
                   for x in then if x not in now]
        if not errors and now != then:
            errors.append(f'{part}: declaration order changed')
    return errors


def self_test(text, frozen, package):
    assert not compare(declaration_set(text, package), frozen)
    anchor = '  void _vpSetState(VoidCallback fn) => setState(fn);\n'
    assert anchor in text
    cases = {
        'new State member': text.replace(anchor, anchor + '  int _planted = 0;\n', 1),
        'removed State member': text.replace(anchor, '', 1),
        'new top-level class': text + '\nclass PlantedTopLevel {}\n',
        'new top-level function': text + '\nvoid plantedFunction() {}\n',
        'new adapter class': text + '\nclass _VpPlantedHostAdapter {}\n',
    }
    for label, mutated in cases.items():
        assert mutated != text, label
        errors = compare(declaration_set(mutated, package), frozen)
        assert errors, 'accepted: ' + label
        print('end-state negative ' + label + ': rejected')
    shrunk = dict(frozen, state_members=[m for m in frozen['state_members'] if m != '_vpSetState'])
    assert not compare(declaration_set(cases['removed State member'], package), shrunk)
    print('end-state positive: a removal recorded in the frozen list passes (shrink-only)')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--freeze', action='store_true',
                        help='write the current set (reviewed raise/shrink procedure only)')
    args = parser.parse_args()
    ensure_parser_package(args.parser_package.parent.parent, args.parser_package)
    text = (ROOT / FACADE).read_text()
    current = declaration_set(text, args.parser_package)
    if args.freeze:
        (ROOT / FROZEN).write_text(json.dumps(dict(
            schema=1, facade=FACADE, procedure='video-player-screen-plan.md: reviewed raise procedure',
            **current), indent=1) + '\n')
    frozen = json.loads((ROOT / FROZEN).read_text())
    if args.self_test:
        self_test(text, frozen, args.parser_package)
    errors = compare(current, frozen)
    for error in errors:
        print(error)
    print(('FAIL' if errors else 'PASS') + f": {len(current['top_level'])} top-level declarations, "
          f"{len(current['state_members'])} State members, {len(current['adapters'])} adapters frozen")
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
