"""Independent raw binder assertions and real-manifest capture negatives."""
import copy


def self_test(original, sources, rows, config, package, leaves):
    from check_verbatim_moves import parse
    from check_settings_moves import all_nodes, check
    from debrify_tv_source_reader import validate
    from occurrence_field_bindings import failures, lexical_setter_failures, aligned
    source = config['source']
    lookup = all_nodes(parse(sources, package, occurrence_bindings=True))
    assert not failures(leaves, lookup, rows, source, config)
    def member(text):
        return parse({'fixture': 'class Test { '+text+' }'}, package,
                     occurrence_bindings=True)['fixture']['declarations'][0]['members'][0]
    # Whole-block declarations shadow before declaration. Nested closures may
    # capture a later outer function; that is distinct from an early invocation.
    cases = [
        ('void f() { print(startRandom); final startRandom = true; }','startRandom','early:'),
        ('void f() { action(); void action() {} }','action','early:'),
        ('void f() { final call = () { action(); }; void action() {} call(); }','action','decl:'),
        ('void f(bool startRandom) { { final startRandom = false; print(startRandom); } print(startRandom); }','startRandom','decl:'),
        ('void f() { for (final startRandom in values) { print(startRandom); } }','startRandom','decl:'),
        ('void f() { try {} catch (startRandom) { print(startRandom); } }','startRandom','decl:'),
        ('void f(Object value) { if (value case final bool startRandom) { print(startRandom); } }','startRandom','decl:'),
    ]
    for text, name, prefix in cases:
        refs=[o for o in member(text)['occurrences'] if o['name']==name]
        assert refs and all(o['binding'].startswith(prefix) for o in refs),(text,refs)
        assert all(o['tokenIndex'] is not None for o in refs)
    selectors=member('void f() { print(cacheEntry.status); print(parsed.channels); }')['occurrences']
    assert any(o['name']=='status' and o['kind']=='selector' and o['qualifierTokens']==['cacheEntry'] for o in selectors)
    assert any(o['name']=='channels' and o['kind']=='selector' and o['qualifierTokens']==['parsed'] for o in selectors)
    # Formatting commas inside selector targets must follow the same AST
    # punctuation policy as a complete declaration; argument separators and
    # a one-field record's required comma remain part of the target.
    plain=member('void f() { Map.of(values).remove(key); values.where((v) => keep(v)).toList(); }')
    formatted=member('void f() { Map.of(values,).remove(key); values.where((v) => keep(v,),).toList(); }')
    selected=lambda node: [(o['name'], o['qualifierTokens']) for o in node['occurrences'] if o['kind']=='selector']
    assert selected(plain)==selected(formatted), (selected(plain), selected(formatted))
    different=member('void f() { Map.of(values, other).remove(key); values.where((v) => keep(v)).toList(); }')
    assert selected(plain)!=selected(different)
    record=member('void f() { receive((value,),).remove(key); }')
    assert any(o['name']=='remove' and o['qualifierTokens']==['receive','(','(','value',',',')',')'] for o in record['occurrences'])
    unknown=member('void f() { _owners.settings.unregistered(); }')
    assert len(aligned(unknown,config))==len(unknown['occurrences'])
    def row_node(identity):
        r=next(r for r in rows if r['original_name']==identity)
        return r,(r['destination_file'],r['destination_class'],r['new_name'])
    def both_reject(key,node,body,label):
        changed=dict(sources)
        changed[key[0]]=changed[key[0]][:node['start']]+body+changed[key[0]][node['end']:]
        assert check(original,changed,rows,source,package,context_guard=True,config=config),label
        try:validate(original,changed,rows,config,package)
        except ValueError:pass
        else:raise AssertionError('Reader accepted binding mutation '+label)
    def reject(identity,before,after,expected):
        row,key=row_node(identity);node=lookup[key];assert before in node['text'],(identity,before)
        changed=copy.deepcopy(lookup)
        body=node['text'].replace(before,after,1)
        changed[key]=member(body)
        changed[key]['owner']=key[1];changed[key]['name']=key[2]
        errors=failures(leaves,changed,rows,source,config,members={identity})
        assert any(expected in e for e in errors),(identity,before,errors)
        both_reject(key,node,body,identity+' '+expected)
        print('TV binding '+identity+' '+expected+': checker and reader rejected')
    reject('_DebrifyTVScreenState._loadSettings','_owners.settings.startRandom = startRandom','startRandom = startRandom','field qualification lost')
    reject('_DebrifyTVScreenState._loadSettings','_owners.settings.startRandom = startRandom','_owners.settings.startRandom = _owners.settings.startRandom','lexical binding changed')
    reject('_DebrifyTVScreenState._persistImportedZipChannels','_owners.library.channels','channels','field qualification lost')
    reject('_DebrifyTVScreenState._watchChannel','cacheEntry.status','_owners.session.status','Occurrence alignment changed')
    reject('_DebrifyTVScreenState._importZipBytes','parsed.channels','_owners.library.channels','Occurrence alignment changed')
    identity='_DebrifyTVScreenState._buildSettingsCard';row,key=row_node(identity);node=lookup[key]
    assert '_owners.settings.startRandom' in node['text'] and 'startRandom' in node['text']
    # Balanced field/local substitution preserves identifier counts but changes
    # which declaration the paired occurrences read. Select reads from the raw
    # binder, so the local declaration itself remains valid Dart.
    field=next(o for o in node['occurrences'] if o['name']=='startRandom' and o['kind']=='selector' and o['qualifierTokens']==['_owners','.','settings'])
    local=next(o for o in node['occurrences'] if o['name']=='startRandom' and o['kind']=='lexical' and o['binding'].startswith('decl:') and o['role']=='read')
    body=node['text']; edits=[(field['offset']-node['start']-len('_owners.settings.'),len('_owners.settings.startRandom'),'startRandom'),(local['offset']-node['start'],len('startRandom'),'_owners.settings.startRandom')]
    for at,size,value in sorted(edits,reverse=True):body=body[:at]+value+body[at+size:]
    changed=copy.deepcopy(lookup);changed[key]=member(body)
    assert failures(leaves,changed,rows,source,config,members={identity})
    both_reject(key,node,body,'balanced field/local capture')
    for identity in config['lexical_state_setters']:
        row,key=row_node(identity);node=lookup[key]
        refs=[o for o in node['occurrences'] if o['name']=='setState' and o['binding'].startswith('decl:')]
        assert refs
        for ref in refs:
            relative=ref['offset']-node['start'];body=node['text'];body=body[:relative]+'_deps.setState'+body[relative+8:]
            changed=copy.deepcopy(lookup);changed[key]=member(body)
            assert lexical_setter_failures(leaves,changed,rows,source,config)
            both_reject(key,node,body,identity+' lexical setter')
    # All seven records: declarations alone pass; injecting a bare reference
    # into any field initializer fails independently of verbatim comparison.
    for owner in ['library','stage','settings','session','prefetch','progress','focus']:
        row=next(r for r in rows if r['destination_class']=='DebrifyTv'+owner.capitalize()+'State' and leaves[r['original_name']]['variables'])
        key=(row['destination_file'],row['destination_class'],row['new_name'])
        node=member('Object injected = startRandom;')
        changed={**lookup,(key[0],key[1],'injected'):node}
        assert any('Bare owner field reference' in e for e in failures(leaves,changed,rows,source,config,members=set()))
        full=next(v for k,v in lookup.items() if k[0]==key[0] and k[1]==key[1])
        both_reject((key[0],key[1],full['name']),full,full['text']+'\nObject injected = startRandom;','bare initializer '+owner)
    changed={**lookup,(config['feature']+'/presentation/legacy_debrify_tv/debrify_tv_feedback.dart','DebrifyTvFeedback','injected'):member('void injected() { print(startRandom); }')}
    assert any('Bare owner field reference' in e for e in failures(leaves,changed,rows,source,config,members=set()))
    key=next(k for k in lookup if k[1]=='DebrifyTvFeedback');node=lookup[key]
    both_reject(key,node,node['text']+'\nvoid injected() { print(startRandom); }','bare section reference')
    print('TV raw binder scopes, selectors, seven records, balanced capture and lexical setters: PASS')
