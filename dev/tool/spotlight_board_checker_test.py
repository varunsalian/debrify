#!/usr/bin/env python3
"""Real Spotlight configuration positives and contract mutation negatives."""
import copy
import csv
import json
import re
import subprocess


def self_test(package=None):
    from check_settings_moves import ROOT, all_nodes, check, tokens, configured
    from check_settings_moves import builder_context_signature, normalize
    from check_verbatim_moves import parse
    from torbox_callback_identity import arguments, callback_argument, check_callback_identities
    config = json.loads((ROOT / 'dev/tool/spotlight_board_checker_config.json').read_text())
    rows = list(csv.DictReader((ROOT / 'dev/tool/spotlight_board_manifest.tsv').open(), delimiter='\t'))
    source = config['source']
    original = subprocess.check_output(['git', 'show', config['baseline']+':'+source], cwd=ROOT, text=True)
    sources = {source: (ROOT / source).read_text()}
    sources.update({str(p.relative_to(ROOT)): p.read_text() for p in (ROOT / config['feature']).rglob('*.dart')})
    lookup = all_nodes(parse(sources, package))
    assert not check(original, sources, rows, source, package, context_guard=True, config=config)
    print('Spotlight real configuration positive: PASS')
    from spotlight_board_source_reader_test import self_test as reader_self_test
    reader_self_test(package)

    def located(name):
        row = next(r for r in rows if r['original_name'] == name)
        key = (row['destination_file'], row['destination_class'], row['new_name'])
        if key not in lookup:
            owner, _, leaf = name.rpartition('.')
            key = (source, owner, leaf or name)
            if key not in lookup:
                key = (source, config.get('type_renames', {}).get(owner, owner), leaf or name)
        return key, lookup[key]

    for case in json.loads((ROOT / 'dev/tool/spotlight_board_verbatim_fixtures/cases.json').read_text()):
        key, node = located(case['member'])
        changed = dict(sources)
        body = node['text']
        if case['mutation'] == 'drop_stop':
            body, count = re.subn(r'(?:widget|view)\s*\.\s*onTrailerStop\?\.call\(\);', '', body, count=1)
        elif case['mutation'] == 'drop_dispose':
            body, count = re.subn(r'[\w.]+(?:\?\.)?(?:cancel|dispose)\(\);', '', body, count=1)
        elif case['mutation'] == 'wrong_this':
            body, count = re.subn(r'(onInteraction\?\.call\()\s*(?:this|cardState)', r'\1anotherState', body, count=1)
        elif case['mutation'] == 'dispose_order':
            matches = list(re.finditer(r'[\w.]+(?:\?\.)?(?:cancel|dispose)\(\);', body))
            assert len(matches) >= 2
            a,b = matches[:2]
            body = body[:a.start()]+b.group()+body[a.end():b.start()]+a.group()+body[b.end():]
            count = 1
        elif case['mutation'] == 'gated_trailer':
            body, count = re.subn(r'if \((?:widget|view)\.trailer != null\)', lambda m: m.group()[:-1]+' && false)', body, count=1)
        elif case['mutation'] == 'rebound_trailer_start':
            body,count = re.subn(r'(onTrailerStart:\s*)(?:widget|view)\.onTrailerStop', r'\1() {}', body, count=1)
        else:
            assert case['before'] in body, case
            body = body.replace(case['before'],case['after'],1)
            count = 1
        assert count == 1, case
        changed[key[0]] = changed[key[0]][:node['start']]+body+changed[key[0]][node['end']:]
        assert check(original, changed, rows, source, package, context_guard=True, config=config), case['name']
        print('Spotlight fixture '+case['name']+': rejected')

    # Identity checker alone: full token/scaffold failures cannot conceal a
    # wrapper or a second instance of the same class at any callback site.
    for spec in config['callback_identities']:
        for site in spec['sites']:
            key,node = located(site['member'])
            values=tokens(node)
            call=site['call']
            for row in rows:
                if row['original_name'].split('.')[-1] == call and row['new_name'] in values:
                    call=row['new_name']; break
            expressions=arguments(values,call)
            occurrence=site.get('occurrence',0)
            expression=callback_argument(expressions[occurrence],site)
            starts=[i for i in range(len(values)-1) if values[i:i+2]==[call,'(']]
            start=starts[occurrence]+2
            position=next(i for i in range(start,len(values)) if values[i:i+len(expression)]==expression)
            for label,replacement in [('receiver swap',['secondInstance','.',expression[-1]]),('wrapper',['(',')','=>',*expression,'(',')'])]:
                mutated=copy.deepcopy(lookup); edited=list(values)
                edited[position:position+len(expression)]=replacement
                mutated[key]['tokens']=[{'text':t,'offset':i} for i,t in enumerate(edited)]
                mutated[key]['formatCommas']=[]
                assert check_callback_identities(mutated,rows,source,config), (spec['name'],label)
                print('Spotlight callback '+spec['name']+' '+label+': rejected')

    # Config-scoped bound-State context guard, before normalization. The real
    # card method legitimately reads State mounted twice over lexical context.
    _,node=located('_CardState._buildCard')
    body=node['text']
    if 'cardState.mounted' not in body:
        body=re.sub(r'(?<![.\w])mounted\b','cardState.mounted',body)
    def method(text):
        return parse({'bound':'class Bound { '+text+' }'},package)['bound']['declarations'][0]['members'][0]
    positive=method(body)
    signature=builder_context_signature(positive,['cardState'])
    assert signature.get('state-mounted')==2, signature
    assert not signature.get('state-context-over-parameter'),signature
    for before,after in [('AppThemeScope.of(context)','AppThemeScope.of(cardState.context)'),('context.findRenderObject()','cardState.context.findRenderObject()'),('ensureVisible(\n            context','ensureVisible(\n            cardState.context')]:
        if before not in body:
            before='ensureVisible(\n'+re.search(r'ensureVisible\(\n(\s*)context',body)[1]+'context'
            after=before.replace('context','cardState.context')
        assert before in body
        assert builder_context_signature(method(body.replace(before,after,1)),['cardState']) != signature
        print('Spotlight bound-State lexical context '+before.split('(')[0]+': rejected')
    row=next(r for r in rows if r['original_name']=='_CardState._buildCard')
    with configured(config):
        assert normalize(['this'],rows,row)==normalize(['cardState'],rows,row)
        assert normalize(['cardState','.','setState'],rows,row)!=normalize(['setState'],rows,row)
        for receiver in ['card','anotherState','widget','_deps.state']:
            assert normalize(receiver.split('.'),rows,row)!=normalize(['this'],rows,row)
        another=next(r for r in rows if r['original_name']=='_CardState._setHover')
        assert normalize(['cardState'],rows,another)!=normalize(['this'],rows,another)
    with configured(config):
        for setter in [['boardState', '.', 'setState'], ['(', 'callback', ')', '=>', 'setState', '(', 'callback', ')']]:
            assert normalize(setter, rows, row) != normalize(['setState'], rows, row)
    print('Spotlight board setState tear-off and wrapper negatives: rejected')
    from spotlight_board_binding_fixtures import self_test as binding_self_test
    binding_self_test(original, sources, rows, source, config, package)
    print('Spotlight exact bound-this positive, receiver-shadowing/protected setState/outside-site negatives: PASS')

    # Exercise the real whole-tree checker for the one registered header
    # addition; generic token mismatch alone cannot mask a header-rule failure.
    additions=config['class_header_additions']['SpotlightBoardState']
    probe=dict(sources)
    state_key=(source,'','SpotlightBoardState')
    declaration=lookup[state_key]
    brace=declaration['text'].index('{')
    header=declaration['text'][:brace]
    header=re.sub(r'\s+implements\s+SpotlightBoardWidgetView\s*$', '', header)
    approved=header.rstrip()+' implements SpotlightBoardWidgetView '
    probe[source]=probe[source][:declaration['start']]+approved+declaration['text'][brace:]+probe[source][declaration['end']:]
    probe[additions['activation_file']]='abstract class SpotlightBoardWidgetView {}\n'
    probe_config=copy.deepcopy(config)
    probe_config.setdefault('additional_owners',[]).append({'file':additions['activation_file'],'owner':'','names':['SpotlightBoardWidgetView']})
    assert not check(original,probe,rows,source,package,context_guard=True,config=probe_config)
    for label,replacement in [
        ('changed superclass',approved.replace('State<SpotlightBoard>','State<StatefulWidget>')),
        ('dropped mixin',re.sub(r'with\s+MetadataPresentationMixin<SpotlightBoard>','',approved)),
        ('extra mixin',approved.replace('implements',', OtherMixin implements')),
        ('extra interface',approved.replace('SpotlightBoardWidgetView','SpotlightBoardWidgetView, OtherView')),
        ('wrong interface',approved.replace('SpotlightBoardWidgetView','OtherView')),
        *[(modifier,approved.replace('class SpotlightBoardState',modifier+' class SpotlightBoardState')) for modifier in ['final','base','sealed']],
    ]:
        assert replacement!=approved
        mutant=dict(probe);mutant[source]=mutant[source].replace(approved,replacement,1)
        errors=check(original,mutant,rows,source,package,context_guard=True,config=probe_config)
        assert any('Widget class header changed: SpotlightBoardState' in e for e in errors),(label,errors)
        print('Spotlight registered header '+label+': rejected')
    mutant=dict(probe);mutant[source]=mutant[source].replace('extends StatefulWidget {','extends StatefulWidget implements SpotlightBoardWidgetView {',1)
    assert any('Widget class header changed: SpotlightBoard' in e for e in check(original,mutant,rows,source,package,context_guard=True,config=probe_config))
    print('Spotlight header addition on another class: rejected')
    view_row=next(r for r in rows if r['original_name']=='SpotlightBoardState._heroArt')
    with configured(config):
        assert normalize(['view','.','hero'],rows,view_row)==normalize(['widget','.','hero'],rows,view_row)
        assert normalize(['view','.','groundOf'],rows,view_row)==normalize(['SpotlightBoard','.','groundOf'],rows,view_row)
        assert normalize(['view','.','groundLowOf'],rows,view_row)!=normalize(['SpotlightBoard','.','groundOf'],rows,view_row)
        assert normalize(['0.32'],rows,view_row)!=normalize(['SpotlightBoard','.','leftThirdBusy'],rows,view_row)
    print('Spotlight view/static substitutions and swap/inlining negatives: PASS')
