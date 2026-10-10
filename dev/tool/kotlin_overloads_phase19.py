"""Pipeline volatile provenance and separate before/after metadata writer owners."""
import json
from pathlib import Path
import subprocess

import check_kotlin_moves as k
from kotlin_overloads_phase16 import historical_pins, field_declarations
from kotlin_overloads_phase18 import historical_receivers, audit_historical, audit_shuffle_constructor
from kotlin_volatile_chains import reviewed_chains, audit_read_chains

ACTIVITY = 'com.debrify.app.tv.AndroidTvTorrentPlayerActivity'
PIPELINE = 'com.debrify.app.tv.TvMediaPipelineController'
RECEIVER = 'com.debrify.app.tv.TvEpisodeMetadataReceiver'
START = 'com.debrify.app.tv.TvPlaybackStartController'


def writer_owners():
    return dict(before=dict(handleMetadataUpdate=ACTIVITY, replacePayloadWithStremioTvItem=START),
                after=dict(handleMetadataUpdate=RECEIVER, replacePayloadWithStremioTvItem=START))


def constant_pins():
    return [dict(original='class AndroidTvTorrentPlayerActivity/fun setupPlayer()',
                 name=name, value=value, count=1)
            for name, value in [('ACTIVITY_SERVICE', 'activity'), ('CONNECTIVITY_SERVICE', 'connectivity')]]


def retained_shuffle(manifest):
    return json.loads(subprocess.check_output(['git', '-C', str(k.ROOT), 'show',
        manifest['base'] + ':dev/tool/kotlin_moves/tvplayer_p18.json'], text=True))['source_bound_initializers']


def validate(manifest, original, current, units, nodes, moved):
    historical_pins(manifest)
    historical_receivers(manifest)
    if manifest.get('identity_writer_owners') != writer_owners():
        raise ValueError('metadata before/after writer owner-map coverage differs')
    if manifest.get('retained_identity') != dict(descriptor='Ljava/lang/String;',
            writers=['handleMetadataUpdate', 'replacePayloadWithStremioTvItem'], reader='playlistController'):
        raise ValueError('frozen identity writer/reader proof coverage differs')
    expected = [dict(original='class AndroidTvTorrentPlayerActivity/property ' + name,
                     name=name, descriptor=descriptor)
                for name, descriptor in [('currentIptvHttpHeaders', 'Ljava/util/Map;'),
                                         ('iptvStrictTsActive', 'Z'), ('activeVodHeaders', 'Lkotlin/Pair;')]]
    if manifest.get('borrowed_volatile') != expected:
        raise ValueError('borrowed volatile field proof coverage differs')
    for pin in expected:
        name = pin['original']
        if name in moved:
            raise ValueError('loader-thread volatile field must remain Activity-owned')
        before, after = nodes['original'][name], nodes[manifest['source']][name]
        def annotated(unit, node):
            pairs = k.tokens(unit, node['start'], node['end'])
            return any(pairs[i:i + 2] == [('AT', '@'), ('IDENTIFIER', 'Volatile')]
                       for i in range(len(pairs) - 1))
        if not all(annotated(units[path], node) for path, node in
                   (('original', before), (manifest['source'], after))):
            raise ValueError('borrowed loader-thread field must retain @Volatile')
        if before['declared_type'] != after['declared_type']:
            raise ValueError('borrowed loader-thread field descriptor changed')
    if manifest.get('volatile_read_chains') != reviewed_chains():
        raise ValueError('volatile read-chain descriptor/role coverage differs')
    if manifest.get('constant_receivers') != constant_pins():
        raise ValueError('Context inlined-constant coverage differs')
    shuffle = retained_shuffle(manifest)
    if manifest.get('retained_source_bound_initializers') != shuffle:
        raise ValueError('retained ShowShuffle source-bound proof coverage differs')
    for pin in shuffle:
        frozen = subprocess.check_output(['git', '-C', str(k.ROOT), 'show',
            manifest['base'] + ':' + pin['source']], text=True)
        if (k.ROOT / pin['source']).read_text() != frozen:
            raise ValueError('retained ShowShuffle source changed')
    if manifest.get('readiness_reads') != [] or manifest.get('initializer_timing') != []:
        raise ValueError('phase-19 has no initializer proofs or readiness reads')


def audit_constants(pins, instructions, owner):
    scope = [i for i in instructions if i['owner'] == owner and ' setupPlayer(' in i['method']]
    for pin in pins:
        matches = [i for i in scope if i['opcode'] in ('ldc', 'ldc_w') and i['operand'] == 'String ' + pin['value']]
        if len(matches) != pin['count'] or any(i['opcode'] == 'getstatic' and
                ('.' + pin['name'] + ':') in i['operand'] for i in scope):
            raise ValueError('Context constant must retain reviewed inlined String value/count')


def audit_compiled(manifest, original, current, before_folder, after_folder):
    from check_kotlin_overloads import bytecode, typed_bytecode
    from kotlin_overloads_phase17 import audit_compiled as prior_audit, audit_host_setters
    maps = writer_owners()
    if manifest.get('identity_writer_owners') != maps:
        raise ValueError('metadata before/after writer owner-map coverage differs')
    results = prior_audit(manifest, original, current, before_folder, after_folder,
        identity_writer_owners=maps['after'], identity_writer_owners_before=maps['before'])
    before, after = typed_bytecode(before_folder), typed_bytecode(after_folder)
    audit_host_setters([p for p in manifest['borrowed_volatile'] if p['name'] == 'activeVodHeaders'],
                      after, 'playbackStartController')
    for folder, instructions, relocated in ((before_folder, before, False), (after_folder, after, True)):
        results += audit_read_chains(manifest['volatile_read_chains'], folder, instructions, relocated)
        audit_constants(manifest['constant_receivers'], instructions, PIPELINE if relocated else ACTIVITY)
        pin = manifest['retained_source_bound_initializers'][0]
        path = str(Path(manifest['source']).parent / 'TvPlaybackNavigator.kt')
        frozen = subprocess.check_output(['git', '-C', str(k.ROOT), 'show', manifest['base'] + ':' + path], text=True)
        node = next(n for n in k.walk(k.parse({'frozen': frozen})['frozen']['declarations'])
                    if n['id'] == 'class TvPlaybackNavigator/property showShuffle')
        audit_shuffle_constructor(pin, instructions, 'com.debrify.app.tv.TvPlaybackNavigator',
                                  frozen.count('\n', 0, node['start']) + 1)
    return results + audit_historical(manifest, bytecode(before_folder), bytecode(after_folder))
