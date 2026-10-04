"""Real-config original/moved probes and the actual retained-preamble join."""
import copy
import csv
import json
import re
import subprocess


def self_test(package=None):
    from check_settings_moves import ROOT, check, all_nodes, configured, tokens, normalize, declaration_tokens, normalized_accessor_tokens
    from check_verbatim_moves import parse
    from torbox_callback_identity import arguments, callback_argument, check_callback_identities
    from playback_settings_partition import check_partition, virtual
    config = json.loads((ROOT/'dev/tool/playback_settings_checker_config.json').read_text())
    rows = list(csv.DictReader((ROOT/'dev/tool/playback_settings_manifest.tsv').open(), delimiter='\t'))
    source, state = config['source'], '_ExternalPlayerSettingsPageState'
    original = subprocess.check_output(['git', 'show', config['baseline']+':'+source], cwd=ROOT, text=True)
    sources = {source: (ROOT/source).read_text()}
    sources.update({p.relative_to(ROOT).as_posix(): p.read_text() for p in (ROOT/config['feature']).rglob('*.dart')})
    lookup = all_nodes(parse(sources, package))
    assert not check(original, sources, rows, source, package, partition=True, context_guard=True, config=config)
    print('Playback real configuration positive: PASS')

    def located(key):
        row = next(r for r in rows if r['original_name']==key)
        dest = (row['destination_file'], row['destination_class'], row['new_name'])
        if dest not in lookup:
            owner, _, name = key.rpartition('.')
            dest = (source, owner, name)
        return dest, lookup[dest]

    def reject(label, key, mutation, move=False):
        dest, node = located(key)
        text = mutation(node['text'])
        assert text != node['text'], label
        changed = dict(sources)
        changed[dest[0]] = changed[dest[0]][:node['start']] + ('' if move else text) + changed[dest[0]][node['end']:]
        if move:
            changed['moved_lifecycle.dart'] = 'class WrongOwner { '+text+' }'
        assert check(original, changed, rows, source, package, partition=True, context_guard=True, config=config), label
        print('Playback real fixture '+label+': rejected')

    def swap_disposals(text, last=False):
        resources = [m for m in re.finditer(r'[\w.]+\.dispose\(\);', text) if m[0]!='super.dispose();']
        assert len(resources)==42
        a,b = resources[-2:] if last else resources[:2]
        return text[:a.start()]+b[0]+text[a.end():b.start()]+a[0]+text[b.end():]
    reject('first two disposals swapped', state+'.dispose', swap_disposals)
    reject('last two disposals swapped', state+'.dispose', lambda text: swap_disposals(text, True))
    reject('lifecycle moved out of State', state+'.dispose', lambda text: text+'\n', move=True)
    _, init = located(state+'.initState')
    listeners = [r for r in init['references'] if r['name']=='addListener']
    assert len(listeners)==36
    spans=[]
    for ref in listeners[:2]:
        start = ref['statementOffset']-init['start']
        callback = next(c for c in init['callbacks'] if c['offset']>ref['offset'] and '/' not in c['scope'])
        end = init['text'].index(';', callback['end']-init['start'])+1
        spans.append((start,end))
    (a,b),(c,d)=spans
    reject('listener order changed', state+'.initState', lambda text: text[:a]+text[c:d]+text[b:c]+text[a:b]+text[d:])
    reject('self-push moved into feature', state+'._openPlayerSettings', lambda text: text+'\n', move=True)

    # Every named callback site is tested directly, so a scaffold mismatch
    # cannot conceal an identity-resolver regression.
    for spec in config['callback_identities']:
        site=spec['sites'][0]
        dest,node=located(site['member'])
        occurrence=site.get('occurrence',0)
        if 'partition_element' in site:
            piece=next(p for p in config['callback_partitions'][site['member']]
                       if p['first_element']<=site['partition_element']<p['end_element'])
            piece_dest=(piece['file'],piece['owner'],piece['name'])
            if piece_dest in lookup:
                dest,node=piece_dest,lookup[piece_dest]
                occurrence=site['piece_occurrence']
        call_name=located(site['call_member'])[1]['name'] if 'call_member' in site else site['call']
        call=arguments(tokens(node),call_name)[occurrence]
        arg=callback_argument(call,site)
        pattern=[site['named_argument'],':',*arg]
        values=tokens(node)
        matches=[i for i in range(len(values)) if values[i:i+len(pattern)]==pattern]
        assert len(matches)==1,(spec['name'],pattern)
        index=matches[0]+2
        for label,replacement in [
          ('wrapping closure',['(',')','=>',*arg,'(',')']),
          ('same-class receiver swap',['otherSameClass','.',arg[-1]]),
          ('wrong member',[*arg[:-1],arg[-1]+'Changed']),
          ('missing named argument',None),
        ]:
            changed=copy.deepcopy(lookup)
            altered=list(values)
            if replacement is None:
                altered[index-2]='missingNamedArgument'
            else:
                altered[index:index+len(arg)]=replacement
            changed[dest]['tokens']=[{'text':v,'offset':i,'comment':False} for i,v in enumerate(altered)]
            changed[dest]['formatCommas']=[]
            assert check_callback_identities(changed,rows,source,config),(spec['name'],label)
            print('Playback callback '+spec['name']+' '+label+': rejected')

    # The retained private State action is borrowed under a legal public
    # record field. Its exact alias must still resolve to that State instance.
    spec = next(s for s in config['callback_identities'] if s['callback_member']==state+'._openPlayerSettings')
    site = spec['sites'][0]
    dest,node = located(site['member'])
    changed = copy.deepcopy(lookup)
    vals = tokens(node)
    argument = callback_argument(arguments(vals, site['call'])[site.get('occurrence', 0)], site)
    index = next(i for i in range(len(vals)) if vals[i:i+2+len(argument)]==['onTap',':',*argument])+2
    vals[index:index+len(argument)] = ['_deps','.','openPlayerSettings']
    changed[dest]['tokens'] = [{'text':v,'offset':i,'comment':False} for i,v in enumerate(vals)]
    changed[dest]['formatCommas'] = []
    assert not check_callback_identities(changed,rows,source,config)
    with configured(config):
        assert normalize(['_deps','.','openPlayerSettings'],rows)==['_openPlayerSettings']
        assert normalize(['otherSameClass','.','openPlayerSettings'],rows)!=['_openPlayerSettings']
        assert normalize(['(',')','=>','_deps','.','openPlayerSettings','(',')'],rows)!=['_openPlayerSettings']
    print('Playback exact retained-State borrowed alias: PASS; receiver/closure negatives rejected')

    accessor_spec = config['test_accessors'][0]
    expected = json.loads((ROOT/accessor_spec['tokens_file']).read_text())
    current_accessor = lookup[(source, '', accessor_spec['name'])]
    with configured(config):
        canonical = normalized_accessor_tokens(expected, accessor_spec, rows)
        if 'composition' not in accessor_spec:
            assert normalized_accessor_tokens(tokens(current_accessor), accessor_spec, rows) == canonical
        # Exercise the receiver normalization directly, independently of scaffold
        # rejection: only the exact frozen owner may supply a snapshot member.
        assert normalized_accessor_tokens(['s', '.', '_defaultAspectIndex'], accessor_spec, rows) == normalized_accessor_tokens(['s', '.', '_values', '.', 'defaultAspectIndex'], accessor_spec, rows)
        assert normalized_accessor_tokens(['otherSameClass', '.', '_values', '.', 'defaultAspectIndex'], accessor_spec, rows) != normalized_accessor_tokens(['s', '.', '_defaultAspectIndex'], accessor_spec, rows)
        assert normalized_accessor_tokens(['s', '.', 'wrongOwner', '.', 'defaultAspectIndex'], accessor_spec, rows) != normalized_accessor_tokens(['s', '.', '_defaultAspectIndex'], accessor_spec, rows)
    print('Playback frozen accessor receiver: PASS; exact-owner negatives rejected')

    # Build the planned join from the REAL formatted original and REAL ranges.
    # Directly exercise its rule, including reconstruction, before it exists.
    before_lookup=all_nodes(parse({source:original},package))
    key=state+'._externalPlayerSettings'
    before=before_lookup[(source,state,'_externalPlayerSettings')]
    row=next(r for r in rows if r['original_name']==key)
    spec=json.loads((ROOT/config['sidecars']['partitions']).read_text())['partitions'][key]
    elements=before['returnedList']['elements']
    retained=original[before['start']:before['bodyOffset']+1]+'\nreturn ['+original[before['returnedList']['offset']+1:elements[0]['end']]+','
    retained=retained.replace('_externalPlayerSettings(', 'externalPlayerSettings(',1)
    retained+='\n'+''.join('..._deps.'+p['name']+'(),\n' for p in spec['slices'])+'];\n}'
    fixture_sources={spec['join_file']:'class '+spec['builder_class']+' { '+retained+' }'}
    for piece in spec['slices']:
        start,end=piece['first_element'],piece['end_element']
        comma=original.index(',',elements[start-1]['end'])
        interior=original[comma+1:elements[end-1]['end']]+','
        preamble='\n'.join(p['text'] for p in before['returnedList']['preamble'] if p['names'][0] in piece['repeated_locals'])
        fixture_sources[piece['file']]='class '+piece['owner']+' { List<Widget> '+piece['name']+'() { '+preamble+'\nreturn ['+interior+'];\n} }'

    def partition_errors(fixture, specification=spec):
        found=all_nodes(parse(fixture,package))
        current=found[(spec['join_file'],spec['builder_class'],'externalPlayerSettings')]
        with configured(config):
            errors=check_partition(before,current,specification,found,rows,package,row)
            if not errors:
                reconstructed=virtual(current,specification,found,fixture,package)
                if declaration_tokens(before,rows,row,original=True)!=declaration_tokens(reconstructed,rows,row):
                    errors.append('Full original reconstructed scope changed')
        return errors
    assert not partition_errors(fixture_sources),partition_errors(fixture_sources)
    print('Playback actual planned retained-preamble join: PASS')
    join=spec['join_file']
    variants={}
    base=fixture_sources[join]
    first='..._deps.'+spec['slices'][0]['name']+'(),'
    second='..._deps.'+spec['slices'][1]['name']+'(),'
    variants['platform pieces reordered']={**fixture_sources,join:base.replace(first,'MARKER').replace(second,first).replace('MARKER',second)}
    variants['piece omitted']={**fixture_sources,join:base.replace(first,'')}
    variants['piece duplicated']={**fixture_sources,join:base.replace(first,first+first)}
    variants['inline E1 changed']={**fixture_sources,join:base.replace("'external'","'debrify'",1)}
    variants['retained preamble changed']={**fixture_sources,join:base.replace('return [','final theme = Theme.of(otherContext); return [',1)}
    ios=spec['slices'][0]['file']
    piece_base=fixture_sources[ios]
    variants['unpermitted extra local']={**fixture_sources,ios:piece_base.replace('return [','final extra = 1; return [',1)}
    first_element=elements[1]['text']
    second_element=elements[2]['text']
    variants['element reordered']={**fixture_sources,ios:piece_base.replace(first_element,'MARKER').replace(second_element,first_element).replace('MARKER',second_element)}
    variants['element omitted']={**fixture_sources,ios:piece_base.replace(first_element+',','',1)}
    variants['element duplicated']={**fixture_sources,ios:piece_base.replace(first_element+',',first_element+','+first_element+',',1)}
    # Split the real E3 collection-if's child list into two complete halves,
    # putting the second half in the next platform piece. All child widgets
    # survive, but one original AST element is now spread across owners.
    element = elements[2]['text']
    child_open = element.index('...[') + 3
    child_close = element.rfind(']')
    child_text = element[child_open + 1:child_close]
    child_node = parse({'children': 'List<Widget> children() { return [' + child_text + ']; }'}, package)['children']['declarations'][0]
    children = child_node['returnedList']['elements']
    assert len(children) > 1
    cut = children[0]['end'] - child_node['returnedList']['offset'] - 1
    first_half = element[:child_open + 1] + child_text[:cut] + ',]'
    second_half = element[:child_open + 1] + child_text[cut:].lstrip().removeprefix(',') + ']'
    linux = spec['slices'][1]['file']
    variants['element split across pieces']={**fixture_sources,
        ios:piece_base.replace(element, first_half, 1),
        linux:fixture_sources[linux].replace('return [', 'return [' + second_half + ',', 1)}
    for label,fixture in variants.items():
        assert fixture!=fixture_sources,label
        try:
            errors=partition_errors(fixture)
        except (ValueError,KeyError,IndexError):
            errors=['Invalid partition AST']
        assert errors,label
        print('Playback partition '+label+': rejected')
