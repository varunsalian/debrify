"""Original and current fixtures from the actual addon-hub manifest/config."""
import copy,csv,json,re,subprocess


def self_test(package=None):
    from check_settings_moves import ROOT,check,all_nodes,configured,tokens
    from check_verbatim_moves import parse
    from torbox_callback_identity import arguments,callback_argument,check_callback_identities
    config=json.loads((ROOT/'dev/tool/addon_hub_checker_config.json').read_text())
    rows=list(csv.DictReader((ROOT/'dev/tool/addon_hub_manifest.tsv').open(),delimiter='\t'))
    source,state=config['source'],'_AddonHubScreenState'
    original=subprocess.check_output(['git','show',config['baseline']+':'+source],cwd=ROOT,text=True)
    original_lookup=all_nodes(parse({source:original},package))
    assert not check_callback_identities(original_lookup,rows,source,config)
    print('Addon hub original-positive proof: all direct tear-offs and closure bindings PASS')
    sources={source:(ROOT/source).read_text()}
    sources.update({p.relative_to(ROOT).as_posix():p.read_text() for p in (ROOT/config['feature']).rglob('*.dart')})
    lookup=all_nodes(parse(sources,package))
    assert not check(original,sources,rows,source,package,context_guard=True,config=config)
    print('Addon hub real configuration positive: PASS')
    def located(key):
        row=next(r for r in rows if r['original_name']==key)
        dest=(row['destination_file'],row['destination_class'],row['new_name'])
        if dest not in lookup:
            owner,_,name=key.rpartition('.')
            dest=(source,owner,name)
        return dest,lookup[dest]
    def reject(label,key,mutate,move=False):
        dest,node=located(key);text=mutate(node['text']);assert text!=node['text'],label
        changed=dict(sources)
        changed[dest[0]]=changed[dest[0]][:node['start']]+('' if move else text)+changed[dest[0]][node['end']:]
        if move:changed['wrong.dart']=('class WrongOwner { '+text+' }') if '.' in key else text
        assert check(original,changed,rows,source,package,context_guard=True,config=config),label
        print('Addon hub real fixture '+label+': rejected')
    def swap(text):
        calls=list(re.finditer(r'[\w.]+\.dispose\(\);',text));a,b=calls[-3:-1]
        return text[:a.start()]+b[0]+text[a.end():b.start()]+a[0]+text[b.end():]
    reject('last two cleanup statements swapped',state+'.dispose',swap)
    reject('cleanup dropped',state+'.dispose',lambda text:text.replace('_remoteEngines.dispose();','',1) if '_remoteEngines.dispose();' in text else re.sub(r'[\w.]+\.remoteEngines\.dispose\(\);','',text,count=1))
    reject('remote engine wrong owner',state+'.dispose',lambda text:re.sub(r'(?<![\w.])([\w.]*remoteEngines|_remoteEngines)\.dispose\(\)',r'otherOwner.\1.dispose()',text,count=1))
    reject('lifecycle moved out of State',state+'.initState',lambda text:text+'\n',True)
    reject('comment reworded','_FocusCardState',lambda text:text.replace('A small scale pop','A different scale pop',1))
    reject('new const',state+'._emptyState',lambda text:text.replace('TextStyle(fontSize: 16','const TextStyle(fontSize: 16',1))
    reject('split widget/State pair','_FocusCardState',lambda text:text+'\n',True)
    # Token-only mutations prove the identity resolver independently of all
    # verbatim/scaffold comparisons. Every single site is rejected alone.
    for label,current in [('original',original_lookup),('current',lookup)]:
        for spec in config['callback_identities']:
            for site in spec['sites']:
                row=next(r for r in rows if r['original_name']==site['member'])
                dest=(row['destination_file'],row['destination_class'],row['new_name'])
                if dest not in current:dest=(source,*site['member'].rpartition('.')[::2])
                node=current[dest];values=tokens(node)
                call_name=site['call']
                call_row=next((r for r in rows if r['original_name']==call_name),None)
                if call_row and call_row['new_name'] in values:call_name=call_row['new_name']
                call=arguments(values,call_name)[site.get('occurrence',0)];arg=callback_argument(call,site)
                # Select the exact callback argument even in nested constructors.
                indices=[i for i in range(len(values)) if values[i:i+len(arg)]==arg]
                if isinstance(site['argument'],str):indices=[i for i in indices if values[i-2:i]==[site['argument'],':']]
                assert len(indices)==1,(label,spec['name'],indices)
                i=indices[0]
                if 'closure' in spec:
                    params=spec['closure']['parameters'];start=len(params)+1;body=arg[start:];opening=body.index('(');invoked=body[:opening]
                    mutations=[('receiver only',[*arg[:start],'otherSameClass','.',invoked[-1],*body[opening:]]),('member only',[*arg[:start],*invoked[:-1],invoked[-1]+'Changed',*body[opening:]]),('argument only',[*arg[:start],*invoked,'(','wrongArgument',')']),('tear-off',invoked),('nested wrapper',[*params,'=>','(',')','=>',*body]),('parameter list',['(','different',')',*arg[len(params):]])]
                else:
                    direct=arg[:-1] if arg[-1:]==['!'] else arg
                    mutations=[('receiver',['otherSameClass','.',direct[-1]]),('member',[*direct[:-1],direct[-1]+'Changed']),('wrapper',['(',')','=>',*direct,'(',')']),('missing argument',[])]
                for kind,replacement in mutations:
                    changed=copy.deepcopy(current);altered=[*values[:i],*replacement,*values[i+len(arg):]]
                    if not replacement and isinstance(site['argument'],str):altered[i-2]='missingNamedArgument'
                    changed[dest]['tokens']=[{'text':v,'offset':n,'comment':False} for n,v in enumerate(altered)];changed[dest]['formatCommas']=[]
                    assert check_callback_identities(changed,rows,source,config),(label,spec['name'],kind)
                    print('Addon hub '+label+' callback '+spec['name']+' '+kind+': rejected')
    isolated=copy.deepcopy(config);isolated['callback_closure_binding']=False
    assert check_callback_identities(original_lookup,rows,source,isolated)
    print('Addon hub closure extension requires config opt-in: PASS')
