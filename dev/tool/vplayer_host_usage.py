#!/usr/bin/env python3
"""Video-player Host-usage audit (modelled on check_tvplayer_host_usage.py).

Parser-based, over the bridge files and the facade:
  1. every member of every `Vp*Host` is used by the code of its own file
     (`<host field>.member`); for a property either accessor counts;
  2. every member of every `_Vp*HostAdapter` (other than its constructor and
     its State field) overrides a member its Host declares, with the same kind;
  3. same-name forwarders (P21a post-gate candidate): an adapter accessor
     whose whole body reads or writes one State member or one member chain
     (`_s.x`, `_s._x`, `_s.widget.x`, `_s._collab.x`, `_s.a.b.x`; `.` or
     `?.`), and an adapter method whose body is `=> _s.<chain>.<name>(...)`,
     forward the member of their own name: the last name of the chain is the
     member's name or `_` + it (`setState` -> `_vpSetState` is the one rule),
     unless listed in RENAMED (exact, reviewed; empty: review P2-1 found no
     chain forwarder of another name). Only names are compared, not setter
     values or method arguments (the P21 move check covers those);
  4. every other adapter member is listed in NON_FORWARDERS with its exact
     body; any other shape (parenthesised, `??`, `!`, ternary, cascade,
     block body, ...) fails as "unrecognised adapter member shape", and the
     forwarder counts are pinned exactly in FORWARDER_COUNTS (re-review P2-A);
and each Host has exactly one adapter. Known exceptions are listed exactly.
This is a lexical call-site audit, not a claim that every branch runs.
"""
import argparse
import copy
import json
from pathlib import Path
import re

from check_verbatim_moves import ROOT, parse, ensure_parser_package

FACADE = 'lib/screens/video_player_screen.dart'
BRIDGE = 'lib/features/video_player/presentation/legacy_video_player'
# Host members used outside `_host.member` in their file (exact).
UNUSED_EXCEPTIONS = {}
# Adapter accessors whose single State read/write (or the last name of their
# chain) has a different name: 'Adapter.member[@set]' -> the dotted chain after
# `_s.` (exact). Empty: the P21b review found no real exception.
RENAMED = {}
# Registered open exceptions the audit lists (completion audit item 5): the
# live duplicate `_isAnyOverlayOpen` (same body as `_anyPlayerOverlayOpen`),
# forwarded to VpControlsRuntime for the pointer wake. Exit: the build
# decomposition re-forwards it to `_anyPlayerOverlayOpen` or removes it.
REGISTERED_DUPLICATES = {'_VpControlsRuntimeHostAdapter.isAnyOverlayOpen': '_isAnyOverlayOpen'}
# Pinned same-name forwarder counts (re-review P2-A): direct accessors (826
# getters + 342 setters), chain accessors (152 + 13), methods; 1,769 in total.
# A forwarder rewritten into another shape lowers a count and fails here.
FORWARDER_COUNTS = dict(direct=1168, chain=165, method=436)
# The 22 adapter members that are not forwarders (19 getters, 3 methods):
# 'Adapter.member' -> its exact code tokens after `=>` (exact; none reads
# `_s.<x>`). Any other adapter member that is not a recognised forwarder fails.
NON_FORWARDERS = {
    '_VpPlayerStartupHostAdapter.isAndroid': 'VpS2Hooks . isAndroid ;',
    '_VpMediaOpenHostAdapter.isIOS': 'VpS2Hooks . isIOS ;',
    '_VpMediaOpenHostAdapter.visibilityOwner': '_s ;',
    '_VpPlayerSubscriptionsHostAdapter.isIOS': 'VpS2Hooks . isIOS ;',
    '_VpPlayerSubscriptionsHostAdapter.visibilityOwner': '_s ;',
    '_VpPlayerInstanceHostAdapter.createPlayer':
        'VideoPlayerScreenTestHooks . _createPlayer ( configuration : configuration ) ;',
    '_VpPlayerInstanceHostAdapter.createVideoController':
        'VideoPlayerScreenTestHooks . _createVideoController ( player , configuration : configuration , ) ;',
    '_VpPlayerDefaultsHostAdapter.tvReleaseLogChannel': '_VideoPlayerScreenState . _tvReleaseLogChannel ;',
    '_VpRendererFallbackHostAdapter.isAndroid': 'VpS2Hooks . isAndroid ;',
    '_VpRendererFallbackHostAdapter.isAndroidRendererValidation': 'VpS2Hooks . isAndroidRendererValidation ;',
    '_VpDecoderProbeHostAdapter.tvReleaseLogChannel': '_VideoPlayerScreenState . _tvReleaseLogChannel ;',
    '_VpDecoderProbeHostAdapter.isAndroidRendererValidation': 'VpS2Hooks . isAndroidRendererValidation ;',
    '_VpStartupCandidatesHostAdapter.isAndroid': 'VpS2Hooks . isAndroid ;',
    '_VpIptvZapLadderHostAdapter.iptvZapPageSize': '_VideoPlayerScreenState . _kIptvZapPageSize ;',
    '_VpIptvZapRingHostAdapter.iptvZapPageSize': '_VideoPlayerScreenState . _kIptvZapPageSize ;',
    '_VpResumeRestoreHostAdapter.readLocalResume':
        'VideoPlayerScreen . readLocalResume ( contentId : contentId , resumeKey : resumeKey ,'
        ' enhanced : enhanced , ) ;',
    '_VpIptvRecordingHostAdapter.isIOS': 'VpS2Hooks . isIOS ;',
    '_VpSubtitleApplyHostAdapter.isIOS': 'VpS2Hooks . isIOS ;',
    '_VpSubtitleApplyHostAdapter.isAndroid': 'VpS2Hooks . isAndroid ;',
    '_VpPipLifecycleHostAdapter.pipOwner': '_s ;',
    '_VpPipLifecycleHostAdapter.isIOS': 'VpS2Hooks . isIOS ;',
    '_VpPipLifecycleHostAdapter.isAndroid': 'VpS2Hooks . isAndroid ;',
}


def code(node):
    return [t['text'] for t in node['tokens'] if not t['comment']]


def kind(member):
    """('get'|'set'|'method'|'field', name) for a class member."""
    values = code(member)
    name = member['name']
    if member['kind'].startswith('FieldDeclaration'):
        return 'field'
    if member['kind'].startswith('ConstructorDeclaration'):
        return 'constructor'
    if member.get('isSetter'):
        return 'set'
    index = next((i for i, v in enumerate(values) if v == name), None)
    if index and values[index - 1] == 'get':
        return 'get'
    return 'method'


def field_names(member):
    return [v['name'] for v in member.get('variables') or []]


def hosts_of(units):
    hosts, users = {}, {}
    for path, unit in units.items():
        if path == FACADE:
            continue
        for node in unit['declarations']:
            if re.fullmatch(r'Vp\w+Host', node['name']):
                members = {}
                for member in node['members']:
                    k = kind(member)
                    names = field_names(member) if k == 'field' else [member['name']]
                    for name in names:
                        members.setdefault(name, set()).add('property' if k in ('get', 'set', 'field') else k)
                hosts[node['name']] = dict(path=path, members=members)
    for path, unit in units.items():
        if path == FACADE:
            continue
        for node in unit['declarations']:
            for member in node['members']:
                if not member['kind'].startswith('FieldDeclaration'):
                    continue
                values = code(member)
                for host in hosts:
                    if host in values and hosts[host]['path'] == path:
                        for name in field_names(member):
                            users.setdefault(host, set()).add(name)
    return hosts, users


def usage_errors(units, hosts, users, exceptions):
    errors, used_total = [], 0
    for host, spec in sorted(hosts.items()):
        receivers = users.get(host, set())
        if not receivers:
            errors.append('Host without a collaborator field: ' + host)
            continue
        unit = units[spec['path']]
        values = [t['text'] for t in unit['unitTokens'] if not t['comment']]
        seen = {values[i + 2] for i in range(len(values) - 2)
                if values[i] in receivers and values[i + 1] in ('.', '?.')}
        for name in sorted(spec['members']):
            if name in seen:
                used_total += 1
            elif name not in exceptions.get(host, ()):
                errors.append('unused Host member: ' + host + '.' + name)
        for name in exceptions.get(host, ()):
            if name in seen or name not in spec['members']:
                errors.append('stale Host-usage exception: ' + host + '.' + name)
    return errors, used_total


def method_forwarder_errors(adapter, member, errors):
    """`=> _s.a.b.name(...)`: the last name of the chain is the member's own.

    The one rule: `setState` forwards to the State's `_vpSetState` wrapper.
    Returns 1 for a recognised method forwarder, None for any other shape.
    """
    body = code(member)
    if '=>' not in body:
        return None
    tail = body[body.index('=>') + 1:]
    if tail[:2] != ['_s', '.']:
        return None
    chain, i = [], 2
    while i < len(tail) and re.fullmatch(r'\w+', tail[i]):
        chain.append(tail[i])
        if i + 1 < len(tail) and tail[i + 1] in ('.', '?.'):
            i += 2
        else:
            break
    name = member['name']
    if not chain:
        return None
    if chain[-1] not in (name, '_' + name) and (name, chain[-1]) != ('setState', '_vpSetState'):
        errors.append('renamed forwarder: ' + adapter + '.' + name + ' -> _s.' + '.'.join(chain))
    return 1


def accessor_chain(tail, setter):
    """The names of `_s.a.b.c;` (getter) or `_s.a.b.c = v;` (setter), or None."""
    if tail[:2] != ['_s', '.']:
        return None
    chain, i = [], 2
    while i < len(tail) and re.fullmatch(r'\w+', tail[i]):
        chain.append(tail[i])
        if i + 1 < len(tail) and tail[i + 1] in ('.', '?.'):
            i += 2
        else:
            i += 1
            break
    else:
        return None
    rest = tail[i:]
    if setter:
        return chain if len(rest) == 3 and rest[0] == '=' and re.fullmatch(r'\w+', rest[1]) and rest[2] == ';' else None
    return chain if rest == [';'] else None


def adapter_errors(facade, hosts, renamed, non_forwarders=None):
    non_forwarders = NON_FORWARDERS if non_forwarders is None else non_forwarders
    errors, forwarders, adapters, listed, method_forwarders, chained = [], 0, {}, set(), 0, 0
    others = {}

    def other(adapter, member, k):
        """A member that is no recognised forwarder: it must be listed exactly."""
        body = code(member)
        key = adapter + '.' + member['name'] + ('@set' if k == 'set' else '')
        others[key] = ' '.join(body[body.index('=>') + 1:]) if '=>' in body else None
        if key not in non_forwarders:
            errors.append('unrecognised adapter member shape: ' + key)
        elif non_forwarders[key] != others[key]:
            errors.append('non-forwarder adapter member changed: ' + key)

    for node in facade['declarations']:
        if not re.fullmatch(r'_Vp\w+HostAdapter', node['name']):
            continue
        values = code(node)
        host = values[values.index('implements') + 1] if 'implements' in values else None
        if host not in hosts:
            errors.append('adapter implements no bridge Host: ' + node['name'])
            continue
        if host in adapters:
            errors.append('second adapter for one Host: ' + host)
        adapters[host] = node['name']
        declared = hosts[host]['members']
        for member in node['members']:
            k = kind(member)
            if k == 'constructor' or (k == 'field' and field_names(member) == ['_s']):
                continue
            names = field_names(member) if k == 'field' else [member['name']]
            want = 'property' if k in ('get', 'set', 'field') else k
            for name in names:
                if want not in declared.get(name, set()):
                    errors.append('adapter-only member: ' + node['name'] + '.' + name)
            if k == 'method':
                found = method_forwarder_errors(node['name'], member, errors)
                if found is None:
                    other(node['name'], member, k)
                else:
                    method_forwarders += found
                continue
            if k not in ('get', 'set'):
                other(node['name'], member, k)
                continue
            body = code(member)
            chain = accessor_chain(body[body.index('=>') + 1:], k == 'set') if '=>' in body else None
            if chain is None:
                other(node['name'], member, k)
                continue
            target = '.'.join(chain)
            forwarders += 1
            chained += len(chain) > 1
            name = member['name']
            if node['name'] + '.' + name in REGISTERED_DUPLICATES:
                listed.add(node['name'] + '.' + name + ' -> _s.' + target)
            if chain[-1] not in (name, '_' + name):
                if renamed.get(node['name'] + '.' + name + ('@set' if k == 'set' else '')) != target:
                    errors.append('renamed forwarder: ' + node['name'] + '.' + name + ' -> _s.' + target)
    for host in sorted(set(hosts) - set(adapters)):
        errors.append('Host without an adapter: ' + host)
    stale = [key for key, target in renamed.items()
             if key.split('.')[0] not in adapters.values()]
    errors += ['stale renamed-forwarder exception: ' + key for key in stale]
    errors += ['stale non-forwarder exception: ' + key for key in sorted(set(non_forwarders) - set(others))]
    expected = {key + ' -> _s.' + target for key, target in REGISTERED_DUPLICATES.items()}
    if listed != expected:
        errors.append('registered duplicate forwarders changed: ' + str(sorted(listed ^ expected)))
    return errors, (forwarders, method_forwarders, chained), len(adapters), sorted(listed)


def sources(root=ROOT):
    files = {FACADE: (root / FACADE).read_text()}
    files.update({p.relative_to(root).as_posix(): p.read_text() for p in sorted((root / BRIDGE).glob('*.dart'))})
    return files


def audit(files, package, exceptions=None, renamed=None, non_forwarders=None):
    units = parse(files, package, ownership=True)
    hosts, users = hosts_of(units)
    errors, used = usage_errors(units, hosts, users, UNUSED_EXCEPTIONS if exceptions is None else exceptions)
    more, forwarders, adapters, listed = adapter_errors(units[FACADE], hosts, RENAMED if renamed is None else renamed,
                                                       non_forwarders)
    counts = dict(direct=forwarders[0] - forwarders[2], chain=forwarders[2], method=forwarders[1])
    if counts != FORWARDER_COUNTS:
        more.append('forwarder counts changed: ' + json.dumps(counts) + ' (pinned ' + json.dumps(FORWARDER_COUNTS) + ')')
    members = sum(len(h['members']) for h in hosts.values())
    return errors + more, dict(hosts=len(hosts), host_members=members, used=used, adapters=adapters,
                               same_name_forwarders=forwarders[0], same_name_chain_forwarders=forwarders[2],
                               same_name_method_forwarders=forwarders[1],
                               unused_exceptions=UNUSED_EXCEPTIONS,
                               renamed_forwarders=len(RENAMED), non_forwarders=len(NON_FORWARDERS),
                               registered_open_exceptions=listed)


# (label, facade text, replacement, the pinned count it lowers): each plant
# rewrites the first occurrence of a same-name forwarder (re-review P2-A).
SHAPE_NEGATIVES = [
    ('parenthesised getter', 'Duration get duration => _s._duration;', 'Duration get duration => (_s._duration);', 'direct'),
    ('?? getter', 'mk.Player get player => _s._player;', 'mk.Player get player => _s._player ?? _s._player;', 'direct'),
    ('ternary getter', 'bool get hideSeekbar => _s.widget.hideSeekbar;',
     'bool get hideSeekbar => _s.mounted ? _s.widget.hideSeekbar : false;', 'chain'),
    ('! getter', 'Duration get position => _s._position;', 'Duration get position => _s._position!;', 'direct'),
    ('cascade setter', 'set activeMediaUserPaused(bool v) => _s._activeMediaUserPaused = v;',
     'set activeMediaUserPaused(bool v) => _s.._activeMediaUserPaused = v;', 'direct'),
    ('parenthesised setter', 'set sleepStopLatched(bool v) => _s._sleepStopLatched = v;',
     'set sleepStopLatched(bool v) => (_s._sleepStopLatched = v);', 'direct'),
    ('block-bodied getter', 'bool get canZapIptvChannel => _s._zapRing.canZapIptvChannel;',
     'bool get canZapIptvChannel {\n    return _s._zapRing.canZapIptvChannel;\n  }', 'chain'),
    ('block-bodied method', 'double dockBand(double legacy) => _s._dockBand(legacy);',
     'double dockBand(double legacy) {\n    return _s._dockBand(legacy);\n  }', 'method'),
]


def self_test(files, package):
    errors, _ = audit(files, package)
    assert not errors, errors
    path = next(p for p in sorted(files) if p.endswith('vp_transition_overlay.dart'))
    text = files[path]
    unused = text.replace('  bool get mounted;\n', '  bool get mounted;\n  int get plantedUnused;\n', 1)
    assert unused != text
    adapter = files[FACADE].replace('class _VpTransitionOverlayHostAdapter implements VpTransitionOverlayHost {\n',
                                    'class _VpTransitionOverlayHostAdapter implements VpTransitionOverlayHost {\n'
                                    '  int get plantedUnused => 0;\n', 1)
    assert adapter != files[FACADE]
    # The planted adapter members are listed non-forwarders, so each negative
    # isolates its own rule.
    planted = lambda name: dict(NON_FORWARDERS, **{'_VpTransitionOverlayHostAdapter.' + name: '0 ;'})
    found, _ = audit(dict(files, **{path: unused, FACADE: adapter}), package, non_forwarders=planted('plantedUnused'))
    assert found == ['unused Host member: VpTransitionOverlayHost.plantedUnused'], found
    print('host-usage negative unused Host member: rejected')
    found, _ = audit(dict(files, **{FACADE: adapter.replace('  int get plantedUnused => 0;\n',
                                                            '  int get adapterOnly => 0;\n', 1)}), package,
                     non_forwarders=planted('adapterOnly'))
    assert found == ['adapter-only member: _VpTransitionOverlayHostAdapter.adapterOnly'], found
    print('host-usage negative adapter-only member: rejected')
    swapped = files[FACADE].replace('set tvStaticMessage(String v) => _s._tvStaticMessage = v;',
                                    'set tvStaticMessage(String v) => _s._tvStaticSubtext = v;', 1)
    assert swapped != files[FACADE]
    found, _ = audit(dict(files, **{FACADE: swapped}), package)
    assert found == ['renamed forwarder: _VpTransitionOverlayHostAdapter.tvStaticMessage -> _s._tvStaticSubtext'], found
    print('host-usage negative renamed (crossed) forwarder: rejected')
    # A chained accessor of another name (review P2-1): `_s.widget.<other>`.
    chained = files[FACADE].replace('int? get contentSeason => _s.widget.contentSeason;',
                                    'int? get contentSeason => _s.widget.contentEpisode;', 1)
    assert chained != files[FACADE]
    found, _ = audit(dict(files, **{FACADE: chained}), package)
    assert found == ['renamed forwarder: _VpPlayerStartupHostAdapter.contentSeason -> _s.widget.contentEpisode'], found
    print('host-usage negative renamed chain forwarder (_s.widget): rejected')
    # The same through a collaborator field, for a getter and a setter.
    chained = files[FACADE].replace('SkipSegment? get activeSkipSegment => _s._skip.activeSkipSegment;',
                                    'SkipSegment? get activeSkipSegment => _s._skip.pendingSkipSegment;', 1)
    chained = chained.replace('set skipSegmentsMediaReady(bool v) => _s._skip.skipSegmentsMediaReady = v;',
                              'set skipSegmentsMediaReady(bool v) => _s._skip.skipSegmentsEnabled = v;', 1)
    assert chained.count('_s._skip.pendingSkipSegment;') == 1 and chained.count('_s._skip.skipSegmentsEnabled = v;') == 1
    found, _ = audit(dict(files, **{FACADE: chained}), package)
    assert found == ['renamed forwarder: _VpTvRemoteHostAdapter.activeSkipSegment -> _s._skip.pendingSkipSegment',
                     'renamed forwarder: _VpPlayerSubscriptionsHostAdapter.skipSegmentsMediaReady'
                     ' -> _s._skip.skipSegmentsEnabled'], found
    print('host-usage negative renamed chain forwarder (_s._collab getter and setter): rejected')
    line = next(l for l in files[FACADE].splitlines() if '=> _s._controlsRuntime.scheduleAutoHide()' in l)
    crossed = files[FACADE].replace(line, line.replace('_controlsRuntime.scheduleAutoHide()', '_controlsRuntime.toggleControls()'), 1)
    found, _ = audit(dict(files, **{FACADE: crossed}), package)
    assert len(found) == 1 and found[0].startswith('renamed forwarder: ') and found[0].endswith(
        '.scheduleAutoHide -> _s._controlsRuntime.toggleControls'), found
    print('host-usage negative crossed method forwarder: rejected')
    # Re-review P2-A: a forwarder rewritten into a shape the audit does not
    # parse fails (and lowers the pinned counts) instead of being skipped.
    for label, before, after, kind_ in SHAPE_NEGATIVES:
        assert files[FACADE].count(before) >= 1, before
        found, _ = audit(dict(files, **{FACADE: files[FACADE].replace(before, after, 1)}), package)
        name = re.search(r'(?:get|set) (\w+)|(\w+)\(', before)
        name = (name.group(1) or name.group(2)) + ('@set' if before.startswith('set ') else '')
        lowered = dict(FORWARDER_COUNTS, **{kind_: FORWARDER_COUNTS[kind_] - 1})
        assert len(found) == 2 and re.fullmatch(r'unrecognised adapter member shape: _Vp\w+HostAdapter\.'
                                                + re.escape(name), found[0]) \
            and found[1] == ('forwarder counts changed: ' + json.dumps(lowered)
                             + ' (pinned ' + json.dumps(FORWARDER_COUNTS) + ')'), found
        print('host-usage negative ' + label + ': rejected: ' + found[0] + ' | ' + found[1])
    listed = files[FACADE].replace('bool get isAndroid => VpS2Hooks.isAndroid;', 'bool get isAndroid => VpS2Hooks.isIOS;', 1)
    assert listed != files[FACADE]
    found, _ = audit(dict(files, **{FACADE: listed}), package)
    assert found == ['non-forwarder adapter member changed: _VpPlayerStartupHostAdapter.isAndroid'], found
    print('host-usage negative changed non-forwarder body: rejected')
    found, _ = audit(files, package, non_forwarders=dict(NON_FORWARDERS, **{'_VpPipLifecycleHostAdapter.gone': '_s ;'}))
    assert found == ['stale non-forwarder exception: _VpPipLifecycleHostAdapter.gone'], found
    print('host-usage negative stale non-forwarder exception: rejected')
    found, _ = audit(files, package, exceptions={'VpTransitionOverlayHost': ['mounted']})
    assert found == ['stale Host-usage exception: VpTransitionOverlayHost.mounted'], found
    print('host-usage negative stale exception: rejected')
    print('host-usage self-test: PASS')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    ensure_parser_package(args.parser_package.parent.parent, args.parser_package)
    files = sources()
    if args.self_test:
        self_test(files, args.parser_package)
    errors, report = audit(files, args.parser_package)
    if args.output:
        args.output.write_text(json.dumps(dict(errors=errors, **report), indent=2) + '\n')
    for error in errors:
        print(error)
    print(('FAIL' if errors else 'PASS') + ': ' + json.dumps(report))
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
