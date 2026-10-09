"""Phase-16 retained dock bindings and volatile identity ownership pins."""
import json
from pathlib import Path
import re
import subprocess

import check_kotlin_moves as k


def historical_pins(manifest):
    revision = manifest['earlier_destinations']['revision']
    if revision != manifest['base']:
        raise ValueError('retained dock binding baseline must be the phase base')
    previous = json.loads(subprocess.check_output([
        'git', '-C', str(k.ROOT), 'show', revision + ':dev/tool/kotlin_moves/tvplayer_p15.json'], text=True))
    pins = previous['find_view_assignments']
    if manifest.get('retained_view_bindings') != pins:
        raise ValueError('retained phase-15 view-binding coverage/descriptors differ')
    return previous, pins


def validate(manifest, original, current, units, nodes, moved):
    previous, pins = historical_pins(manifest)
    expected_reads=[]
    for site in units['original']['callable_references']:
        row=next((r for name,r in moved.items() if nodes['original'][name]['start']<=site['start']<nodes['original'][name]['end']),None)
        if row and site['callee'] in ('nextBackdrop','startupGateView'):
            name=site['callee'];before='::'+name+'.isInitialized'
            if original[site['start']:site['end']+len('.isInitialized')] != before:
                raise ValueError('unreviewed readiness property reference')
            line=original.count('\n',0,site['start'])+1
            expected_reads.append(dict(original=row['original'],line=line,context=original.splitlines()[line-1].strip(),field=name,getter=name+'Ready'))
    if manifest.get('readiness_reads')!=expected_reads:
        raise ValueError('readiness reference audit coverage differs from original PSI')
    # Every destination type remains exactly the old Host target type, including
    # nullability. The indexed array target itself moves, its element stores do not.
    fields = {n['selector'].removeprefix('property '): n for n in nodes['original'].values()
              if n['id'].startswith('class AndroidTvTorrentPlayerActivity/property ') and n['id'].count('/') == 1}
    for pin in pins:
        name = pin['field']
        old = fields[name]
        row = moved.get(old['id'])
        if name == 'ottSkinInstalled':
            if row:
                raise ValueError('ottSkinInstalled must remain Activity-owned')
            continue
        if row is None:
            raise ValueError('retained dock binding owner is missing: ' + name)
        new = nodes[row['destination']][row['target']]
        expected = pin['source_type']
        for node in (old, new):
            actual = node.get('declared_type')
            if name == 'ottQualityChips' and node.get('initializer_text') == 'arrayOfNulls<TextView>(3)':
                actual = 'Array<TextView?>'
            if actual != expected:
                raise ValueError('retained dock target type/nullability differs: ' + name)
    expected = {'original': 'class AndroidTvTorrentPlayerActivity/property ottShowName',
                'destination': str(Path(manifest['source']).parent / 'TvDockIdentityPresenter.kt'),
                'target': 'class TvDockIdentityPresenter/property ottShowName',
                'descriptor': 'Ljava/lang/String;', 'writers': ['handleMetadataUpdate', 'replacePayloadWithStremioTvItem'],
                'reader': 'playlistController'}
    if manifest.get('volatile_identity') != expected:
        raise ValueError('volatile identity ownership/access proof coverage differs')
    row = moved[expected['original']]
    old = nodes['original'][row['original']];new = nodes[row['destination']][row['target']]
    if any('@Volatile' not in text[n['start']:n['end']] for text,n in ((original,old),(current[row['destination']],new))):
        raise ValueError('volatile identity annotation must remain on the moved field')


def field_declarations(folder):
    files = sorted(Path(folder).glob('*.class'))
    if not files:
        raise ValueError('compiled classes missing: ' + str(folder))
    raw = subprocess.check_output([str(k.JBR / 'bin/javap'), '-p', '-s', *map(str,files)], text=True)
    result = {};owner = None;field = None;flags = None
    for line in raw.splitlines():
        if re.match(r'^\S.*\b(class|interface)\b', line):
            owner = re.search(r'\b(?:class|interface) (\S+)', line).group(1)
        elif re.match(r'^  (?:private|public|protected) .*;$', line) and '(' not in line:
            field = line.strip().removesuffix(';').split()[-1]
            flags = line.strip().split()[:-1]
        elif field and line.strip().startswith('descriptor:'):
            result[owner,field] = dict(descriptor=line.split(':',1)[1].strip(),volatile='volatile' in flags)
            field = None
        else:
            field = None
    return result


def audit_binding_site(pin, line, before, after):
    """Require exactly one lookup and the reviewed cast/Host store at this site."""
    owner='com.debrify.app.tv.TvControlsDockController'
    field=pin['field'];array='[' in pin['assignment_target']
    target=('get' if array else 'set')+field[0].upper()+field[1:]+(':'+ '()'+pin['descriptor'] if array else ':('+pin['descriptor']+')V')
    evidence=[]
    for instructions in (before,after):
        local=[i for i in instructions if i['owner']==owner and i['line']==line]
        finds=[i for i in local if i['opcode']=='invokevirtual' and '.findViewById:(I)Landroid/view/View;' in i['operand']]
        casts=[i['operand'].removeprefix('class ') for i in local if i['opcode']=='checkcast']
        setters=[i for i in local if i['opcode']=='invokeinterface' and i['operand'].endswith('TvControlsDockController$Host.'+target)]
        if len(finds)!=1 or casts != ([] if pin['cast'] is None else [pin['cast']]):
            raise ValueError('retained findViewById cast presence/type differs: '+pin['context'])
        if len(setters)!=1 or (array and not any(i['opcode']=='aastore' for i in local)):
            raise ValueError('retained findViewById Host descriptor/array store differs: '+pin['context'])
        evidence.append(local)
    return evidence


def audit_identity(pin, before_fields, after_fields, after):
    for fields,owner in ((before_fields,'com.debrify.app.tv.AndroidTvTorrentPlayerActivity'),(after_fields,'com.debrify.app.tv.TvDockIdentityPresenter')):
        if fields.get((owner,'ottShowName')) != dict(descriptor=pin['descriptor'],volatile=True):
            raise ValueError('identity field must retain ACC_VOLATILE and descriptor')
    # Two receiver-path writers and the computed playlist Host read must dispatch
    # to the new identity owner, with exact String descriptors.
    activity='com.debrify.app.tv.AndroidTvTorrentPlayerActivity'
    for method in pin['writers']:
        scope=[i for i in after if i['owner']==activity and re.search(r'\b'+method+r'\(',i['method'])]
        setters=[i for i in scope if i['opcode']=='invokevirtual' and re.search(r'TvDockIdentityPresenter\.setOttShowName(?:\$[\w]+)?:\(Ljava/lang/String;\)V$',i['operand'])]
        if len(setters)!=1:
            raise ValueError('volatile identity writer dispatch differs: '+method)
    readers=[i for i in after if i['owner'].startswith(activity+'$'+pin['reader']) and
             i['opcode']=='invokevirtual' and re.search(r'TvDockIdentityPresenter\.getOttShowName(?:\$[\w]+)?:\(\)Ljava/lang/String;$',i['operand'])]
    if len(readers)!=1:
        raise ValueError('volatile identity playlist Host read dispatch differs')


def audit(manifest, original, current, before, after, before_fields, after_fields):
    previous,pins = historical_pins(manifest)
    old_source = subprocess.check_output(['git','-C',str(k.ROOT),'show',previous['base']+':'+previous['source']],text=True)
    units = k.parse({'previous':old_source})
    old_nodes = {n['id']:n for n in k.walk(units['previous']['declarations'])}
    paths = {r['destination'] for r in pins}
    frozen = {p:subprocess.check_output(['git','-C',str(k.ROOT),'show',manifest['base']+':'+p],text=True) for p in paths}
    frozen_units = k.parse(frozen)
    frozen_nodes = {p:{n['id']:n for n in k.walk(u['declarations'])} for p,u in frozen_units.items()}
    # These methods stay in the frozen phase-15 destination: compare both builds
    # at its actual line positions, not the obsolete pre-phase-15 Activity lines.
    results=[]
    for pin in pins:
        delta = frozen[pin['destination']].count('\n',0,frozen_nodes[pin['destination']][pin['target']]['start']) - old_source.count('\n',0,old_nodes[pin['original']]['start'])
        line = pin['line']+delta
        owner = 'com.debrify.app.tv.TvControlsDockController'
        field = pin['field'];array = '[' in pin['assignment_target']
        target = ('get' if array else 'set')+field[0].upper()+field[1:]+(':'+ '()'+pin['descriptor'] if array else ':('+pin['descriptor']+')V')
        evidence=audit_binding_site(pin,line,before,after)
        new_owner = ('com.debrify.app.tv.AndroidTvTorrentPlayerActivity' if field=='ottSkinInstalled' else
                     'com.debrify.app.tv.TvControlsOverlayController' if field in ('controlsOverlay','pauseButton') else
                     'com.debrify.app.tv.TvDockIdentityPresenter' if field.startswith('ott') and not field.startswith('ottScrub') else
                     'com.debrify.app.tv.TvSeekScrubController')
        for declarations,cls in ((before_fields,'com.debrify.app.tv.AndroidTvTorrentPlayerActivity'),(after_fields,new_owner)):
            if declarations.get((cls,field),{}).get('descriptor')!=pin['descriptor']:
                raise ValueError('retained binding destination field descriptor differs: '+field)
        results.append(dict(site=pin,before=evidence[0],after=evidence[1]))
    audit_identity(manifest['volatile_identity'],before_fields,after_fields,after)
    return results
