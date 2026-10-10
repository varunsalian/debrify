"""Phase-17 borrowed volatile fields, deferred lazies and frozen binding pins."""
import json
from pathlib import Path
import re
import subprocess

import check_kotlin_moves as k
from kotlin_overloads_phase16 import historical_pins, audit_binding_site, field_declarations, audit_identity


def validate(manifest, original, current, units, nodes, moved):
    historical_pins(manifest)
    if manifest.get('retained_identity') != dict(descriptor='Ljava/lang/String;',
            writers=['handleMetadataUpdate','replacePayloadWithStremioTvItem'],reader='playlistController'):
        raise ValueError('frozen identity writer/reader proof coverage differs')
    expected = [dict(original='class AndroidTvTorrentPlayerActivity/property '+name,
                     name=name, descriptor=descriptor)
                for name, descriptor in [('currentIptvHttpHeaders', 'Ljava/util/Map;'),
                                         ('iptvStrictTsActive', 'Z')]]
    if manifest.get('borrowed_volatile') != expected:
        raise ValueError('borrowed volatile field proof coverage differs')
    source = manifest['source']
    for pin in expected:
        name = pin['original']
        if name in moved:
            raise ValueError('loader-thread volatile field must remain Activity-owned')
        before = nodes['original'][name]
        after = nodes[source][name]
        if any('@Volatile' not in text[node['start']:node['end']]
               for text, node in ((original, before), (current[source], after))):
            raise ValueError('borrowed loader-thread field must retain @Volatile')
        if before['declared_type'] != after['declared_type']:
            raise ValueError('borrowed loader-thread field descriptor changed')
    lazy = ['class AndroidTvTorrentPlayerActivity/property '+name
            for name in ('iptvLiveRecovery', 'iptvStartsWithStrictTs')]
    if manifest.get('deferred_lazy') != lazy:
        raise ValueError('deferred lazy proof coverage differs')
    for name in lazy:
        row = moved[name]
        before = nodes['original'][name]
        after = nodes[row['destination']][row['target']]
        if not before.get('lazy_allocation') or not after.get('lazy_allocation'):
            raise ValueError('recovery and device quirks must remain synchronized lazy delegates')
    if manifest.get('readiness_reads') != []:
        raise ValueError('phase-17 has no readiness reference substitutions')


def audit_deferred(instructions):
    owners = ('com.debrify.app.tv.AndroidTvTorrentPlayerActivity',
              'com.debrify.app.tv.TvIptvTuneController',
              'com.debrify.app.tv.TvIptvTwinTrial')
    for instruction in instructions:
        if instruction['owner'] not in owners:
            continue
        if not re.search(r'\b'+re.escape(instruction['owner'])+r'\(', instruction['method']):
            continue
        operand = instruction['operand']
        if ('IptvLiveRecovery.<init>:' in operand or 'IptvDeviceQuirks.' in operand):
            raise ValueError('constructor eagerly evaluated recovery/device-quirk lazy')


def audit_borrowed(pins, fields, instructions):
    owner = 'com.debrify.app.tv.AndroidTvTorrentPlayerActivity'
    for pin in pins:
        if fields.get((owner, pin['name'])) != dict(descriptor=pin['descriptor'], volatile=True):
            raise ValueError('borrowed loader field must retain ACC_VOLATILE and descriptor')
        if any(name == pin['name'] and cls != owner for cls, name in fields):
            raise ValueError('loader field cannot be snapshotted in a controller')
        writes = [i for i in instructions if i['opcode'] == 'putfield' and
                  re.search(r'(?:\.| )'+re.escape(pin['name'])+':'+re.escape(pin['descriptor'])+'$', i['operand'])]
        if not writes or any(i['owner'] != owner for i in writes):
            raise ValueError('loader field writes must dispatch to Activity volatile storage')
        # Kotlin emits Activity access$ setters; the controller invokes the Host
        # setter. A shadow copy in either controller must not become another field.


def audit_host_setters(pins, instructions):
    owner = 'com.debrify.app.tv.AndroidTvTorrentPlayerActivity'
    host = owner+'$iptvTuneController$1'
    for pin in pins:
        suffix = pin['name'][0].upper()+pin['name'][1:]
        descriptor = pin['descriptor']
        for operation in ('get', 'set'):
            scope = [i for i in instructions if i['owner'] == host and
                     re.search(r'\b'+operation+suffix+r'\(',i['method'])]
            target = 'com/debrify/app/tv/AndroidTvTorrentPlayerActivity.access$'+operation+suffix+'$p:'
            signature = '(Lcom/debrify/app/tv/AndroidTvTorrentPlayerActivity;'+(descriptor if operation=='set' else '')+')'+('V' if operation=='set' else descriptor)
            calls = [i for i in scope if i['opcode']=='invokestatic' and i['operand'].endswith(target+signature)]
            if len(calls) != 1:
                raise ValueError('borrowed Host '+operation+' must dispatch to Activity volatile accessor: '+pin['name'])
            storage = [i for i in instructions if i['owner']==owner and
                       'access$'+operation+suffix+'$p(' in i['method'] and
                       i['opcode']==('putfield' if operation=='set' else 'getfield') and
                       i['operand'].endswith(' '+pin['name']+':'+descriptor)]
            if len(storage) != 1:
                raise ValueError('borrowed Host accessor must reach exact Activity volatile storage')


def audit_reflected_lazy_getter(instructions):
    if not any(i['owner']=='com.debrify.app.tv.TvIptvTuneController' and
               ' getIptvLiveRecovery();' in i['method'] for i in instructions):
        raise ValueError('reflected lazy getter must retain the unmangled getIptvLiveRecovery name')


def audit_compiled(manifest, original, current, before_folder, after_folder):
    from check_kotlin_overloads import typed_bytecode
    before, after = typed_bytecode(before_folder), typed_bytecode(after_folder)
    before_fields, after_fields = field_declarations(before_folder), field_declarations(after_folder)
    for instructions, fields in ((before, before_fields), (after, after_fields)):
        audit_deferred(instructions)
        audit_borrowed(manifest['borrowed_volatile'], fields, instructions)
    audit_host_setters(manifest['borrowed_volatile'], after)
    audit_reflected_lazy_getter(after)
    previous, pins = historical_pins(manifest)
    old_source = subprocess.check_output(['git', '-C', str(k.ROOT), 'show',
                                        previous['base']+':'+previous['source']], text=True)
    old_nodes = {n['id']:n for n in k.walk(k.parse({'old':old_source})['old']['declarations'])}
    frozen = {p:subprocess.check_output(['git','-C',str(k.ROOT),'show',manifest['base']+':'+p],text=True)
              for p in {r['destination'] for r in pins}}
    frozen_nodes = {p:{n['id']:n for n in k.walk(u['declarations'])} for p,u in k.parse(frozen).items()}
    results = []
    phase16 = json.loads(subprocess.check_output(['git','-C',str(k.ROOT),'show',
        manifest['base']+':dev/tool/kotlin_moves/tvplayer_p16.json'],text=True))
    field_owners = {r['original'].rsplit('/property ',1)[-1]:Path(r['destination']).stem
                    for r in phase16['declarations'] if r['fate']=='moved' and '/property ' in r['original']}
    for pin in pins:
        delta = frozen[pin['destination']].count('\n',0,frozen_nodes[pin['destination']][pin['target']]['start']) - old_source.count('\n',0,old_nodes[pin['original']]['start'])
        evidence = audit_binding_site(pin, pin['line']+delta, before, after)
        cls = 'com.debrify.app.tv.'+field_owners.get(pin['field'],'AndroidTvTorrentPlayerActivity')
        if any(fields.get((cls,pin['field']),{}).get('descriptor') != pin['descriptor']
               for fields in (before_fields,after_fields)):
            raise ValueError('frozen binding destination field descriptor differs: '+pin['field'])
        results.append(dict(site=pin, before=evidence[0], after=evidence[1]))
    # Phase 16 already moved identity storage: its owner and volatile descriptor
    # are now frozen, and must stay identical in both compiled trees.
    identity = ('com.debrify.app.tv.TvDockIdentityPresenter', 'ottShowName')
    if any(fields.get(identity) != dict(descriptor='Ljava/lang/String;',volatile=True)
           for fields in (before_fields, after_fields)):
        raise ValueError('frozen identity must retain ACC_VOLATILE and descriptor')
    for fields, instructions in ((before_fields,before),(after_fields,after)):
        audit_identity(manifest['retained_identity'], fields, fields, instructions,
                       before_owner=identity[0])
    return results
