"""Stremio TV opt-in launch ledger and original callback expressions."""
import json

_normal_cache = {}


def check_contracts(lookup, rows, source, config, sources=None):
    from check_settings_moves import ROOT, normalize, tokens
    from torbox_callback_identity import arguments, callback_argument
    errors=[]
    signature=json.dumps([rows,config],sort_keys=True)
    def normalized(values,row):
        key=(signature,row['original_name'],tuple(values))
        if key not in _normal_cache: _normal_cache[key]=normalize(values,rows,row)
        return _normal_cache[key]
    node_tokens={}
    call_arguments={}

    by_original={r['original_name']:r for r in rows}
    scaffold_data=json.loads((ROOT/config['sidecars']['scaffolding']).read_text())
    composition=scaffold_data.get('facade_composition',[])
    owner='_StremioTvScreenState'
    records=set(config['occurrence_field_bindings']['record_paths'].values())
    active=any(r['destination_class'] in records and (r['destination_file'],r['destination_class'],r['new_name']) in lookup for r in rows)
    active=active or any((source,owner,s['name']) in lookup for s in composition)
    if active:
        for spec in composition:
            node=lookup.get((source,owner,spec['name']))
            if node is None or tokens(node)!=spec['tokens']:
                errors.append('Stremio TV once-per-State live composition changed: '+spec['name'])
    if config['occurrence_field_bindings'].get('mandatory_qualification'):
        for row in rows:
            if row['original_name'].rpartition('.')[0]!='_StremioTvScreenState': continue
            destination=(row['destination_file'],row['destination_class'],row['new_name'])
            if destination[0]==source or destination not in lookup: continue
            # Unbound State reads cannot become unresolved bare names in a
            # section. Lexical build/builder parameters and picker State stay
            # governed by their original bindings.
            for occurrence in lookup[destination].get('occurrences',[]):
                if (occurrence['name'] in {'context','mounted','setState'}
                    and occurrence['kind']=='lexical' and occurrence['binding']=='unbound'):
                    errors.append('Missing live State callback receiver: '+row['original_name']+' '+occurrence['name'])
    def code(values):return [v for v in values if not v.startswith(('//','/*'))]
    def located(identity):
        row=by_original[identity];owner,_,name=identity.rpartition('.')
        return lookup.get((row['destination_file'],row['destination_class'],row['new_name'])) or lookup[(source,owner,name or identity)]
    picker_names = {name for alias in config['planned_type_aliases']
                    for name in (alias['original_name'], alias['original_name']+'State')}
    for identity in picker_names:
        # These widgets keep their own State. Screen callback substitutions
        # must never normalize a newly introduced dependency receiver here.
        if '_deps' in code(tokens(located(identity))):
            errors.append('Picker State callback routed through screen dependencies: '+identity)
    def call_name(name):
        aliases={a['original_name']:a['alias'] for a in config.get('type_aliases',[])}
        row=by_original.get('_StremioTvScreenState.'+name) or by_original.get(name)
        return aliases[name] if name in aliases else located(row['original_name'])['name'] if row else name
    def calls(identity,name):
        key=(identity,name)
        if identity not in node_tokens: node_tokens[identity]=code(tokens(located(identity)))
        if key not in call_arguments: call_arguments[key]=arguments(node_tokens[identity],name)
        return call_arguments[key]
    for spec in json.loads((ROOT/config['sidecars']['handoff']).read_text())['sites']:
        try:
            row=by_original[spec['original_member']]
            call=calls(spec['original_member'],spec['call'])[spec['occurrence']]
            actual=[(a[0],normalized(a[2:],row)) for a in call if a[1:2]==[':']]
            expected=[(a['name'],normalized(a['tokens'],row)) for a in spec['arguments']]
            if len(call)!=19 or len(actual)!=len(call) or actual!=expected:
                errors.append('Stremio TV handoff argument name/value/order changed: '+spec['site'])
        except (KeyError,IndexError,ValueError):errors.append('Missing Stremio TV handoff: '+spec['site'])
    play=by_original['_StremioTvScreenState._playChannel']
    try: values=code(tokens(located(play['original_name'])))
    except KeyError: return errors+['Missing Stremio TV play workflow']
    pushes=arguments(values,'push')
    if len(pushes)!=2 or any(len(p)!=2 or normalized(p[0],play)!=['context'] or p[1][:2]!=['VideoPlayerLaunchArgs','('] for p in pushes):
        errors.append('Stremio TV push envelope/context/options changed')
    for i,spec in enumerate(json.loads((ROOT/config['sidecars']['callbacks']).read_text())['sites']):
        try:
            row=by_original[spec['member']];site_calls=calls(spec['member'],call_name(spec['call']))
            actual=callback_argument(site_calls[spec['occurrence']],spec)
            if len(site_calls)!=spec['count'] or normalized(actual,row)!=normalized(code(spec['expression']),row):
                errors.append('Stremio TV original callback expression changed: '+str(i))
        except (KeyError,IndexError,ValueError):errors.append('Missing Stremio TV callback site: '+str(i))
    if sources is not None:
        from collections import Counter
        expected=Counter()
        for leaf in config.get('comment_leaves',[]):
            row=next(r for r in rows if r['original_name']==leaf['anchor'])
            dest=(row['destination_file'],row['destination_class'],row['new_name'])
            owner_file=row['destination_file'] if dest in lookup else source
            expected[owner_file,leaf['text']]+=1
        totals=Counter()
        for (_,comment),count in expected.items(): totals[comment]+=count
        for comment,count in totals.items():
            actual=sum(line.rstrip().endswith(comment) for text in sources.values() for line in text.splitlines())
            if actual!=count: errors.append('Free comment leaf total changed: '+comment)
        for (file,comment),count in expected.items():
            actual=sum(line.rstrip().endswith(comment) for line in sources.get(file,'').splitlines())
            if actual != count:
                errors.append('Free comment leaf ownership changed: '+file+' '+comment+' '+str(actual)+' != '+str(count))
    return errors
