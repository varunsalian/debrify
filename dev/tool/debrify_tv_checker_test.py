#!/usr/bin/env python3
"""Real TV configuration, occurrence bindings, ownership and contract negatives."""
import copy
import re


def _self_test(package=None):
    from debrify_tv_architecture_test import self_test as architecture_tests
    architecture_tests()
    from debrify_tv_checker_fixtures import inputs, layout
    from check_settings_moves import all_nodes, check, tokens, configured
    from check_verbatim_moves import parse
    from torbox_callback_identity import argument_ranges, member_occurrences, check_callback_identities
    original, rows, base_config, leaves = inputs(package)
    source=base_config['source']
    assert not check(original,{source:original},rows,source,package,context_guard=True,config=base_config)
    config={**base_config,'type_aliases':base_config['planned_type_aliases']}
    sources=layout(original,rows,config,leaves)
    assert not check(original,sources,rows,source,package,context_guard=True,config=config)
    print('TV real config ORIGINAL and simulated complete positives: PASS')
    from debrify_tv_source_reader_test import self_test as reader_tests
    reader_tests(original,rows,base_config,leaves,package)
    from debrify_tv_binding_fixtures import self_test as binding_tests
    with configured(config):
        binding_tests(original,sources,rows,config,package,leaves)
    lookup=all_nodes(parse(sources,package,occurrence_bindings=True))
    def located(identity):
        row=next(r for r in rows if r['original_name']==identity)
        return (row['destination_file'],row['destination_class'],row['new_name'])
    def reject(identity,label,transform):
        key=located(identity);node=lookup[key];body=transform(node['text'])
        assert body!=node['text'],('Mutation did not change body',label)
        changed=dict(sources);changed[key[0]]=changed[key[0]][:node['start']]+body+changed[key[0]][node['end']:]
        errors=check(original,changed,rows,source,package,context_guard=True,config=config)
        assert errors,('TV guard accepted',label)
        print('TV contract '+label+': rejected')
    def swap_statements(text,a,b):
        assert a in text and b in text
        return text.replace(a,'__FIRST__',1).replace(b,a,1).replace('__FIRST__',b,1)
    dispose='_DebrifyTVScreenState.dispose'
    reject(dispose,'dispose reorder',lambda s:swap_statements(s,'_owners.progress.progress.dispose();','_owners.library.keywordsController.dispose();'))
    reject(dispose,'dispose drop',lambda s:s.replace('MainPageBridge.watchDebrifyTvChannel = null;','',1))
    reject(dispose,'dispose stop awaited',lambda s:s.replace('void dispose() {','void dispose() async {',1).replace('_sections.prefetch.stopPrefetch();','await _sections.prefetch.stopPrefetch();',1))
    reject(dispose,'library listener unregister removed',lambda s:re.sub(r'MainPageBridge.unregisterDebrifyTvLibraryListener\([^;]+;','',s,count=1))
    # Every launch notification, including native/dormant sites, is exercised.
    notifications=0
    for row in rows:
        key=located(row['original_name']);node=lookup[key]
        matches=list(re.finditer(r'MainPageBridge.notifyPlayerLaunching\(\);',node['text']))
        for ordinal,m in enumerate(matches):
            reject(row['original_name'],'notify '+row['original_name']+' #'+str(ordinal),lambda s,m=m:s[:m.start()]+s[m.end():])
            notifications+=1
    assert notifications==15,notifications
    for identity, before, after, label in [
        ('_DebrifyTVScreenState._switchToChannel','Duration(seconds: 5)','Duration(seconds: 0)','switch cooldown'),
        ('_DebrifyTVScreenState._onSpotlightChannelFocused','Duration(milliseconds: 250)','Duration(milliseconds: 251)','stage debounce'),
        ('_DebrifyTVScreenState._handleExportChannels','capability.runIfCurrent(body)','body()','export profile wrapper'),
        ('_parseZipInBackground','compute(_parseZipCompute, bytes)','compute((bytes) => _parseZipCompute(bytes), bytes)','zip compute closure'),
        ('_parseYamlInBackground','compute(_parseYamlCompute, <String, String>{','compute((payload) => _parseYamlCompute(payload), <String, String>{','yaml compute closure'),
        ('_DebrifyTVScreenState._watchWithTorbox','_owners.settings.startRandom','_owners.settings.quickStartRandom','P3 channel option -> quick'),
        ('_DebrifyTVScreenState._watchWithPremiumize','_owners.settings.startRandom','_owners.settings.quickStartRandom','P11 channel option -> quick'),
        ('_DebrifyTVScreenState._watchWithTorbox','_owners.settings.quickShowChannelName','_owners.settings.showChannelName','P3 quick option -> channel'),
        ('_DebrifyTVScreenState._watchWithPremiumize','_owners.settings.quickShowChannelName','_owners.settings.showChannelName','P11 quick option -> channel'),
        ('_DebrifyTVScreenState._watchWithAllDebrid','if (_owners.session.watchCancelled) return;','','post-native masked cancel removed'),
        ('_DebrifyTVScreenState._persistImportedZipChannels','_owners.library.channels = [..._owners.library.channels, ...appendedChannels];','_owners.library.channels = appendedChannels;','ZIP append replaced by assignment'),
        ('_DebrifyTVScreenState._watchWithTorbox','_owners.session.watchCancelled','false','quick cancel removed'),
        ('_DebrifyTVScreenState._viewerForcesNsfw','!ProfilePolicyGuard.allowsSync(ProfileFeature.allowAdultContent)','false','live NSFW getter cached'),
        ('_SpotlightMetaPill','return Container(','return const Container(','new const'),
        ('_DebrifyTVScreenState._watch','// Do not start prefetch until player launches','// Start prefetch later','reworded comment'),
    ]:
        reject(identity,label,lambda s,a=before,b=after:s.replace(a,b,1))
    # Provider conditions at every requestNextChannel occurrence, not a sample.
    for row in rows:
        key=located(row['original_name']);node=lookup[key]
        for ordinal,m in enumerate(re.finditer(r'_owners.settings.(?:quickProvider|provider) ==\s*DebrifyTvConstants.provider(?:RealDebrid|Torbox|PikPak|Premiumize|AllDebrid)',node['text'])):
            reject(row['original_name'],'provider condition '+row['original_name']+' #'+str(ordinal),lambda s,m=m:s[:m.start()]+'false'+s[m.end():])
    stage='_DebrifyTVScreenState._onSpotlightChannelFocused'
    cancel='_owners.stage.spotlightStatsDebounce?.cancel();'
    reject(stage,'debounce cancel after memo return',lambda s:s.replace(cancel,'',1).replace('return;','return;\n    '+cancel,1))
    # Move each prefetch call to the other side of the nearest original close.
    for identity,ordinal in [('_DebrifyTVScreenState._watch',0),('_DebrifyTVScreenState._watch',1),('_DebrifyTVScreenState._watchWithAllDebrid',0)]:
        def reorder(s,ordinal=ordinal):
            starts=list(re.finditer(r'unawaited\(_sections.prefetch.startPrefetch\(\)\);',s));m=starts[ordinal]
            closes=list(re.finditer(r'(?:Navigator.of\(_owners.progress.progressSheetContext!\).pop\(\);|_sections.feedback.closeProgressDialog\(\);)',s))
            close=min(closes,key=lambda a:abs(a.start()-m.start()))
            a,b=sorted([m,close],key=lambda x:x.start())
            return s[:a.start()]+b.group()+s[a.end():b.start()]+a.group()+s[b.end():]
        reject(identity,'P1/P2/P12 prefetch-close '+str(ordinal)+' '+identity,reorder)
    # Bound context, lexical setter and live getter guard runs before erasure.
    reject('_DebrifyTVScreenState._buildTopActionButton','builder context replaced',lambda s:s.replace('AppThemeScope.of(context)','AppThemeScope.of(_deps.context())',1))
    reject('_DebrifyTVScreenState._promptImportUrl','modal setter replaced',lambda s:s.replace('setState(()','_deps.setState(()',1))
    reject('_DebrifyTVScreenState._loadSettings','cached mounted',lambda s:s.replace('_deps.mounted()','cachedMounted',1))
    # Isolate callback identity so verbatim failures cannot conceal acceptance.
    total=0
    for spec in config['callback_identities']:
        for site in spec['sites']:
            key=located(site['member']);node=lookup[key];values=tokens(node)
            if 'assignment_property' in site:
                start=next(i+2 for i,v in enumerate(values[:-1]) if v==site['assignment_property'] and values[i+1]=='=');end=values.index(';',start)
            else:
                call=lookup[located(site['call_member'])]['name'] if 'call_member' in site else site['call']
                spans=argument_ranges(values,call)[site.get('occurrence',0)]
                arg=site.get('named_argument',site.get('argument'))
                if isinstance(arg,int):start,end=spans[arg]
                else:
                    start,end=next((a,b) for a,b in spans if [v for v in values[a:b] if not v.startswith(('//','/*'))][:2]==[arg,':']);start=next(i for i in range(start,end) if values[i]==':')+1
                if 'conditional_member' in site:
                    target=lookup[located(site['conditional_member'])]['name'];positions=[start+j for j in member_occurrences(values[start:end],target)];end=positions[site.get('branch_occurrence',0)]+1;start=end-1
                    while start>=2 and values[start-1]=='.':start-=2
            expression=values[start:end]
            callback=lookup[located(spec['callback_member'])]['name']
            callback_owner=lookup[located(spec['callback_member'])]['owner']
            receiver=next((path for path,owner in config['receiver_owners'].items() if path.startswith(('_owners.','_sections.')) and owner==callback_owner),None)
            assert receiver, (spec['name'],callback)
            same_instance=['secondInstance','.',callback]
            if expression[-1]=='!':same_instance.append('!')
            for label,replacement in [
                ('wrapper',['(',')','=>',*expression,'(',')']),
                ('same class receiver',same_instance),
                ('member swap',['_sections','.','channelWatch','.','requestChannelById' if expression[-1]!='requestChannelById' else 'requestNextChannel']),
                ('cached tear-off',['cachedCallback']),
            ]:
                changed=copy.deepcopy(lookup);bad=values[:start]+replacement+values[end:];changed[key]={**node,'tokens':[{'text':v,'offset':i,'comment':v.startswith(('//','/*'))} for i,v in enumerate(bad)],'formatCommas':[]}
                scoped={**config,'callback_identities':[spec],'callback_receiver_aliases':{**config['callback_receiver_aliases'],'secondInstance':'$OtherState.'+receiver}}
                with configured(scoped):errors=check_callback_identities(changed,rows,source,scoped)
                assert errors,('callback accepted',spec['name'],label)
                total+=1
    print('TV independent callback-identity negatives: '+str(total)+' PASS')


def self_test(package=None):
    # Repeated negatives recheck the same unchanged leaves. Cache only the
    # real normalizer's exact input/output in this fixture process, never AST
    # binding, ownership or a checker result. Keep config/rows alive so ids
    # cannot be reused between nested configured() scopes.
    import json
    import check_settings_moves as settings
    from occurrence_field_bindings import _canonical_name
    import occurrence_field_bindings as bindings
    normalize=settings.normalize
    cache={};inputs={};canonical_cache={}
    def canonical(name,rows,config):
        for value in [rows,config]:inputs[id(value)]=value
        key=(name,id(rows),id(config))
        if key not in canonical_cache:canonical_cache[key]=_canonical_name(name,rows,config)
        return canonical_cache[key]
    def memoized(values,rows,row=None):
        for value in [settings.CONFIG,rows]:
            inputs[id(value)]=value
        key=(id(settings.CONFIG),id(rows),json.dumps(row,sort_keys=True),tuple(values))
        if key not in cache:cache[key]=tuple(normalize(values,rows,row))
        return list(cache[key])
    settings.normalize=memoized
    bindings._canonical_name=canonical
    try:_self_test(package)
    finally:
        settings.normalize=normalize
        bindings._canonical_name=_canonical_name
