"""Playback-start constructor provenance and retained receiver/storage pins."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

import check_kotlin_moves as k
from kotlin_overloads_phase16 import historical_pins, field_declarations
from kotlin_overloads_phase17 import audit_borrowed, audit_host_setters


def reviewed_shuffle(manifest):
    path = str(Path(manifest['source']).parent / 'ShowShuffle.kt')
    text = subprocess.check_output(['git', '-C', str(k.ROOT), 'show',
                                    manifest['base'] + ':' + path], text=True)
    return dict(original='class AndroidTvTorrentPlayerActivity/property showShuffle',
                expression='ShowShuffle()', source=path, revision=manifest['base'],
                sha256=hashlib.sha256(text.encode()).hexdigest(),
                constructor=dict(owner='com/debrify/app/tv/ShowShuffle',
                    descriptor='(Lkotlin/random/Random;ILkotlin/jvm/internal/DefaultConstructorMarker;)V',
                    opcode='invokespecial')), text


def validate_source_bound(manifest, inventory, sources=None):
    expected, frozen = reviewed_shuffle(manifest)
    rows = manifest.get('source_bound_initializers', [])
    if (len(rows) != 1 or {key: rows[0].get(key) for key in expected} != expected
            or set(rows[0]) != {*expected, 'reason'} or not rows[0]['reason']):
        raise ValueError('ShowShuffle source-bound constructor proof coverage differs')
    node = inventory[expected['original']]
    if node.get('initializer_text') != expected['expression'] or node.get('has_delegate'):
        raise ValueError('ShowShuffle requires the exact reviewed zero-argument constructor')
    actual = ((sources or {}).get(expected['source']) if sources is not None
              else (k.ROOT / expected['source']).read_text())
    if actual != frozen:
        raise ValueError('ShowShuffle source changed from reviewed constructor/default/init provenance')


def historical_receivers(manifest):
    expected = []
    for phase in range(3, manifest['phase']):
        previous = json.loads(subprocess.check_output(['git', '-C', str(k.ROOT), 'show',
            manifest['base'] + f':dev/tool/kotlin_moves/tvplayer_p{phase}.json'], text=True))
        expected.extend(dict(phase=phase, site=site) for site in previous['overload_audit'])
    if manifest.get('retained_receiver_sites') != expected:
        raise ValueError('historical receiver audit coverage differs from all earlier manifests')
    return expected


def validate(manifest, original, current, units, nodes, moved):
    historical_pins(manifest)
    historical_receivers(manifest)
    if manifest.get('retained_identity') != dict(descriptor='Ljava/lang/String;',
            writers=['handleMetadataUpdate', 'replacePayloadWithStremioTvItem'], reader='playlistController'):
        raise ValueError('frozen identity writer/reader proof coverage differs')
    expected = [dict(original='class AndroidTvTorrentPlayerActivity/property ' + name,
                     name=name, descriptor=descriptor)
                for name, descriptor in [('currentIptvHttpHeaders', 'Ljava/util/Map;'),
                                         ('iptvStrictTsActive', 'Z'),
                                         ('activeVodHeaders', 'Lkotlin/Pair;')]]
    if manifest.get('borrowed_volatile') != expected:
        raise ValueError('borrowed volatile field proof coverage differs')
    for pin in expected:
        name = pin['original']
        if name in moved:
            raise ValueError('loader-thread volatile field must remain Activity-owned')
        before, after = nodes['original'][name], nodes[manifest['source']][name]
        if any('@Volatile' not in text[node['start']:node['end']]
               for text, node in ((original, before), (current[manifest['source']], after))):
            raise ValueError('borrowed loader-thread field must retain @Volatile')
        if before['declared_type'] != after['declared_type']:
            raise ValueError('borrowed loader-thread field descriptor changed')
    retained = 'class AndroidTvTorrentPlayerActivity/class ShufflePlaybackAttempt'
    row = next((r for r in manifest['declarations'] if r['original'] == retained), {})
    if row.get('fate') != 'retained':
        raise ValueError('ShufflePlaybackAttempt binary owner must remain Activity')
    blocks = manifest.get('preserved_receiver_blocks', [])
    if ([r.get('original') for r in blocks] !=
            ['class AndroidTvTorrentPlayerActivity/fun playMediaDirect(PlaybackItem)',
             'class AndroidTvTorrentPlayerActivity/fun playPikPakVideoWithRetry(PlaybackItem)',
             'class AndroidTvTorrentPlayerActivity/fun playStremioTvPlaybackMap(StremioTvGuideChannel,Map<*, *>,String,String,Boolean)']
            or any(r.get('receiver') != 'player' or r.get('callee') != 'apply'
                   or not r.get('reason') for r in blocks)):
        raise ValueError('ExoPlayer apply receiver-block coverage differs')
    for row in blocks:
        move = moved[row['original']]
        before = nodes['original'][row['original']]
        after = nodes[move['destination']][move['target']]
        for text, node, expression in ((original, before, 'player?.apply {'),
                (current[move['destination']], after, 'host.player?.apply {')):
            if text[node['start']:node['end']].count(expression) != 1:
                raise ValueError('ExoPlayer apply receiver binding changed')
    if manifest.get('readiness_reads') != []:
        raise ValueError('phase-18 has no readiness reference substitutions')


def audit_shuffle_constructor(pin, instructions, owner, line):
    calls = [i for i in instructions if i['owner'] == owner and i['line'] == line
             and 'ShowShuffle.<init>:' in i['operand']]
    expected = pin['constructor']
    if (len(calls) != 1 or calls[0]['opcode'] != expected['opcode'] or
            not calls[0]['operand'].endswith(expected['owner'] + '.<init>:' + expected['descriptor'])):
        raise ValueError('ShowShuffle resolved constructor/default dispatch changed')
    return calls[0]


def audit_historical(manifest, before, after):
    from check_kotlin_overloads import resolve, resolve_inherited
    results = []
    cache = {}
    for row in historical_receivers(manifest):
        phase, pin = row['phase'], row['site']
        if phase not in cache:
            previous = json.loads(subprocess.check_output(['git', '-C', str(k.ROOT), 'show',
                manifest['base'] + f':dev/tool/kotlin_moves/tvplayer_p{phase}.json'], text=True))
            source = subprocess.check_output(['git', '-C', str(k.ROOT), 'show',
                previous['base'] + ':' + previous['source']], text=True)
            tree = k.parse({'old': source})['old']
            cache[phase] = source, {n['id']: n for n in k.walk(tree['declarations'])}
        source, old_nodes = cache[phase]
        key = pin['destination']
        if key not in cache:
            frozen = subprocess.check_output(['git', '-C', str(k.ROOT), 'show',
                manifest['base'] + ':' + key], text=True)
            tree = k.parse({'frozen': frozen})['frozen']
            cache[key] = frozen, {n['id']: n for n in k.walk(tree['declarations'])}
        frozen, frozen_nodes = cache[key]
        delta = (frozen.count('\n', 0, frozen_nodes[pin['target']]['start']) -
                 source.count('\n', 0, old_nodes[pin['original']]['start']))
        owner = 'com.debrify.app.tv.' + pin['target'].split('/')[0].removeprefix('class ')
        resolver = resolve_inherited if pin.get('receiver') == 'implicit-inherited' else resolve
        evidence = []
        for calls in (before, after):
            resolved, sites = resolver([c for c in calls if c['owner'] == owner
                or c['owner'].startswith(owner + '$')], pin,
                pin['call_start_line'] + delta, pin['call_end_line'] + delta)
            evidence.append((resolved, sorted({c['opcode'] for c in sites})))
            if isinstance(resolved, dict) and resolved != pin['expected_after']:
                raise ValueError('frozen inherited receiver differs from reviewed pin')
            if isinstance(resolved, str) and 'expected_after' in pin:
                target, descriptor = resolved.split(':', 1)
                actual = dict(owner=target.rsplit('.', 1)[0], descriptor=descriptor,
                              opcode=evidence[-1][1][0])
                if actual != pin['expected_after']:
                    raise ValueError('frozen argument receiver differs from reviewed pin')
        if evidence[0] != evidence[1]:
            raise ValueError('earlier compiled receiver dispatch changed')
        results.append(dict(phase=phase, site=pin, before=evidence[0], after=evidence[1]))
    return results


def audit_compiled(manifest, original, current, before_folder, after_folder):
    from check_kotlin_overloads import bytecode, typed_bytecode
    from kotlin_overloads_phase17 import audit_compiled as prior_audit
    before, after = typed_bytecode(before_folder), typed_bytecode(after_folder)
    results = prior_audit(manifest, original, current, before_folder, after_folder,
        identity_writer_owners={'replacePayloadWithStremioTvItem':
                                'com.debrify.app.tv.TvPlaybackStartController'})
    for fields, instructions in ((field_declarations(before_folder), before),
                                 (field_declarations(after_folder), after)):
        audit_borrowed(manifest['borrowed_volatile'], fields, instructions)
    audit_host_setters([p for p in manifest['borrowed_volatile']
                       if p['name'] == 'activeVodHeaders'], after, 'playbackStartController')
    pin = manifest['source_bound_initializers'][0]
    row = next(r for r in manifest['declarations'] if r['original'] == pin['original'])
    old = next(n for n in k.walk(k.parse({'old': original})['old']['declarations'])
               if n['id'] == row['original'])
    new = next(n for n in k.walk(k.parse(current)[row['destination']]['declarations'])
               if n['id'] == row['target'])
    for text, node, instructions, owner in ((original, old, before,
            'com.debrify.app.tv.AndroidTvTorrentPlayerActivity'),
            (current[row['destination']], new, after, 'com.debrify.app.tv.TvPlaybackNavigator')):
        audit_shuffle_constructor(pin, instructions, owner, text.count('\n', 0, node['start']) + 1)
    results += audit_historical(manifest, bytecode(before_folder), bytecode(after_folder))
    return results
