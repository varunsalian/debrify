#!/usr/bin/env python3
"""Real catalog config positives and independent per-site identity negatives."""
import copy,csv,json,re,subprocess
from pathlib import Path


def self_test(package=None):
    from check_verbatim_moves import ROOT,parse
    from check_settings_moves import all_nodes,check,tokens
    from torbox_callback_identity import argument_ranges,member_occurrences,check_callback_identities
    config=json.loads((ROOT/'dev/tool/catalog_detail_checker_config.json').read_text())
    rows=list(csv.DictReader((ROOT/'dev/tool/catalog_detail_manifest.tsv').open(),delimiter='\t'))
    source=config['source'];original=subprocess.check_output(['git','show',config['baseline']+':'+source],cwd=ROOT,text=True)
    sources={source:(ROOT/source).read_text()}
    sources.update({str(p.relative_to(ROOT)):p.read_text() for p in (ROOT/config['feature']).rglob('*.dart')})
    lookup=all_nodes(parse(sources,package))
    def verify(changed):return check(original,changed,rows,source,package,context_guard=True,config=config)
    assert not verify(sources),'Catalog real-config positive failed'
    def located(member):
        row=next(r for r in rows if r['original_name']==member)
        key=(row['destination_file'],row['destination_class'],row['new_name'])
        if key not in lookup:
            owner,_,name=member.rpartition('.');key=(source,owner,name)
        return key,lookup[key]
    def mutate(member,label,transform):
        key,node=located(member);changed=dict(sources);text=transform(node['text'])
        assert text!=node['text'],label
        changed[key[0]]=sources[key[0]][:node['start']]+text+sources[key[0]][node['end']:]
        assert verify(changed),'Accepted '+label
    # Isolate the identity resolver; a whole-leaf failure cannot mask a bug.
    for spec in config['callback_identities']:
        for site in spec['sites']:
            key,node=located(site['member']);values=tokens(node)
            spans=argument_ranges(values,site['call'])[site.get('occurrence',0)]
            if isinstance(site['argument'],int):start,end=spans[site['argument']]
            else:
                start,end=next((a,b) for a,b in spans if [v for v in values[a:b] if not v.startswith(('//','/*'))][:2]==[site['argument'],':'])
                start=next(i for i in range(start,end) if values[i]==':')+1
            while values[start].startswith(('//','/*')):start+=1
            if 'conditional_member' in site:
                _,target=located(site['conditional_member'])
                positions=[start+j for j in member_occurrences(values[start:end],target['name'])]
                end=positions[site.get('branch_occurrence',0)]+1;start=end-1
                while start>=2 and values[start-1]=='.':start-=2
            argument=values[start:end]
            # Use another real State callback, including the exact completion /
            # policy swap, so a missing-symbol error cannot explain rejection.
            _,policy=located('_CatalogItemDetailScreenState._onMovieProgressPolicyChanged')
            _,finished=located('_CatalogItemDetailScreenState._loadLocalMovieFinished')
            swapped=finished if argument[-1]==policy['name'] else policy
            target=located(spec['callback_member'])[1] if 'callback_member' in spec else located('CatalogItemDetailScreen.'+spec['expected_identity'].split('.')[-1])[1]
            if swapped['owner']==node['owner']:
                swap_expression=[swapped['name']]
            else:
                instance=config['callback_instances'][swapped['owner']]
                receiver=instance.replace('$State.parts.','_parts.' if node['owner']=='_CatalogItemDetailScreenState' else '_deps.parts.')
                swap_expression=[]
                for part in (receiver+'.'+swapped['name']).split('.'):
                    if swap_expression:swap_expression.append('.')
                    swap_expression.append(part)
            for label,replacement in [('wrapper',['(',')','=>',*argument,'(',')']),('same-class receiver swap',['secondInstance','.',target['name'],*(['!'] if argument[-1]=='!' else [])]),('callback swap',swap_expression)]:
                bad=values[:start]+replacement+values[end:];changed=copy.deepcopy(lookup)
                changed[key]['tokens']=[{'text':v,'offset':i,'comment':v.startswith(('//','/*'))} for i,v in enumerate(bad)];changed[key]['formatCommas']=[]
                assert check_callback_identities(changed,rows,source,{**config,'callback_identities':[spec],'catalog_call_receivers':[],'catalog_live_reads':[],'callback_receiver_aliases':{**config.get('callback_receiver_aliases',{}),'secondInstance':'$OtherInstance.'+target['owner']},'receiver_paths':{**config.get('receiver_paths',{}),'secondInstance':target['owner']}}),'Accepted '+spec['name']+' '+label
    for spec in config['callback_identities']:
        borrowed=config.get('callback_borrowed_getters',{}).get(spec['name'],{})
        if not borrowed:continue
        for site in spec['sites']:
            key,node=located(site['member']);values=tokens(node)
            spans=argument_ranges(values,site['call'])[site.get('occurrence',0)]
            start,end=next((a,b) for a,b in spans if [v for v in values[a:b] if not v.startswith(('//','/*'))][:2]==[site['argument'],':'])
            start=next(i for i in range(start,end) if values[i]==':')+1
            getter=spec['expected_identity'].split('.')[-1]
            bad=values[:start]+['secondDependencies','.',getter,'(',')']+values[end:]
            changed=copy.deepcopy(lookup);changed[key]['tokens']=[{'text':v,'offset':i,'comment':v.startswith(('//','/*'))} for i,v in enumerate(bad)];changed[key]['formatCommas']=[]
            alias={**borrowed,'secondDependencies.'+getter+'()':'$OtherState.widget.'+getter}
            negative={**config,'callback_identities':[spec],'catalog_call_receivers':[],'catalog_live_reads':[],'callback_borrowed_getters':{**config['callback_borrowed_getters'],spec['name']:alias}}
            assert check_callback_identities(changed,rows,source,negative),'Accepted same-type borrowed callback getter receiver swap '+spec['name']
            mutate(site['member'],'wrong borrowed host callback getter '+getter,lambda s,getter=getter:s.replace('_deps.'+getter+'()','_deps.onPlay()',1))
            mutate(site['member'],'missing borrowed host callback getter invocation '+getter,lambda s,getter=getter:s.replace('_deps.'+getter+'()','_deps.'+getter,1))
    for spec in config.get('catalog_borrowed_live_reads',[]):
        mutate(spec['member'],'missing borrowed live getter invocation',lambda s:s.replace('_deps.metadataPreferences()','_deps.metadataPreferences',1))
        mutate(spec['member'],'alternate borrowed live getter receiver',lambda s:s.replace('_deps.metadataPreferences()','otherDeps.metadataPreferences()',1))

    from catalog_detail_callback_identity import check_contracts
    for spec in config['catalog_call_receivers']:
        key,node=located(spec['member']);values=tokens(node)
        sites=[i for i,v in enumerate(values) if v==spec['call'] and values[i+1:i+2]==['(']]
        i=sites[spec['occurrence']];start=i-2
        while start>=2 and values[start-1]=='.':start-=2
        actual=values[start:i-1]
        # Completion notifiers share a callback: receiver identity is decisive.
        replacement=('MdblistService.instance.watchedRevision' if spec['receiver'].startswith('Movie') else 'MovieProgressStorage.movieFinishedRevision').split('.')
        replacement=[v for i,v in enumerate(replacement) for v in (['.'] if i else [])+[v]]
        bad=values[:start]+replacement+values[i-1:];changed=copy.deepcopy(lookup)
        changed[key]['tokens']=[{'text':v,'offset':j,'comment':v.startswith(('//','/*'))} for j,v in enumerate(bad)];changed[key]['formatCommas']=[]
        assert check_contracts(changed,rows,source,{**config,'catalog_call_receivers':[spec],'catalog_live_reads':[]}),'Accepted receiver swap '+str(spec)
    for spec in config['catalog_host_assignments']:
        key,node=located(spec['member']);values=tokens(node)
        start=next(i+3 for i in range(len(values)) if values[i:i+3]==['final',spec['local'],'=']);end=values.index(';',start)
        for bad in [['(',')','=>',*values[start:end]],['otherWidget','.',spec['getter']],['widget','.','wrongCallback']]:
            changed=copy.deepcopy(lookup);changed[key]['tokens']=[{'text':v,'offset':i,'comment':v.startswith(('//','/*'))} for i,v in enumerate(values[:start]+bad+values[end:])];changed[key]['formatCommas']=[]
            assert check_contracts(changed,rows,source,{**config,'catalog_call_receivers':[],'catalog_live_reads':[],'catalog_host_assignments':[spec]}),'Accepted assigned host callback mutation'
    rail=config['catalog_rail_callback'];key,node=located(rail['member']);values=tokens(node)
    target_name=located(rail['target'])[1]['name']
    callback=re.search(r'(?:[A-Za-z_]\w*\.)*'+re.escape(target_name)+r'\b',node['text']);assert callback
    callback_text=callback.group()
    raw_host='_deps.onRecommendationTap()' if '_deps.' in node['text'] else 'widget.onRecommendationTap'
    for label,bad in [('wrapper','(item) => '+callback_text+'(item)'),('receiver','secondInstance.'+target_name),('member',raw_host)]:
        changed=dict(sources);text=node['text'][:callback.start()]+bad+node['text'][callback.end():]
        changed[key[0]]=sources[key[0]][:node['start']]+text+sources[key[0]][node['end']:]
        mutated=all_nodes(parse(changed,package))
        assert check_contracts(mutated,rows,source,{**config,'catalog_call_receivers':[],'catalog_live_reads':[],'catalog_host_assignments':[]}),'Accepted rail '+label
    mutate('_SimklQuickActions','reworded private comment reference',lambda s:s.replace('[_QuickActions]','[CatalogQuickActions]',1))
    for spec in config.get('scaffold_setter_keys',[]):
        key=(spec['file'],spec['owner'],spec['key']);node=lookup[key]
        changed=dict(sources);replacement=node['text'].replace('writeHasBoundSource(value)','writeHasBoundSource(!value)')
        assert replacement!=node['text']
        changed[key[0]]=sources[key[0]][:node['start']]+replacement+sources[key[0]][node['end']:]
        assert verify(changed),'Accepted changed live bound-source setter scaffold'

    for spec in config.get('plain_sections',[]):
        if spec['owner']!='CatalogDetailMetadata':continue
        for name,before,after in [('mounted','_deps.mounted()','!_deps.mounted()'),('setState','_deps.setState','(fn) => _deps.setState(fn)')]:
            key=(spec['file'],spec['owner'],name);node=lookup[key];changed=dict(sources)
            replacement=node['text'].replace(before,after,1);assert replacement!=node['text']
            changed[key[0]]=sources[key[0]][:node['start']]+replacement+sources[key[0]][node['end']:]
            assert verify(changed),'Accepted changed metadata State forwarding getter '+name
    key=(source,'_CatalogItemDetailScreenState','onMetadataPolicyChanged')
    if located('_CatalogItemDetailScreenState.onMetadataPolicyChanged')[0]!=key:
        node=lookup[key];changed=dict(sources)
        changed[source]=sources[source][:node['start']]+node['text'].replace('@override','',1)+sources[source][node['end']:]
        assert verify(changed),'Accepted missing facade override annotation'
        mutate('_CatalogItemDetailScreenState.onMetadataPolicyChanged','override on moved policy body',lambda s:'@override\n  '+s)
        mutate('_CatalogItemDetailScreenState._loadEnrichedMeta','borrowed mixin callback receiver',lambda s:s.replace('_deps.refreshMetadataPresentation','otherDeps.refreshMetadataPresentation',1))
        mutate('_CatalogItemDetailScreenState._loadEnrichedMeta','wrapped borrowed mixin callback',lambda s:s.replace('_deps.refreshMetadataPresentation();','(() => _deps.refreshMetadataPresentation())();',1))

    state='_CatalogItemDetailScreenState.'
    for member,op,expected in [('initState','addListener',3),('dispose','removeListener',3),('initState','addPlaybackReturnListener',1),('dispose','removePlaybackReturnListener',1),('dispose','unsubscribe',1)]:
        _,node=located(state+member)
        calls=list(re.finditer(r'[\w.]+\.'+op+r'\([\s\S]*?\);',node['text']))
        assert len(calls)==expected,(member,op)
        for i,m in enumerate(calls):mutate(state+member,op+' deletion '+str(i),lambda text,m=m:text[:m.start()]+text[m.end():])
    for member in ['_revealCtrl','_hasBoundSource']:
        mutate(state+member,'late becomes eager',lambda text:text.replace('late ','',1))
        key,node=located(state+member);changed=dict(sources);changed[key[0]]=sources[key[0]][:node['start']]+sources[key[0]][node['end']:]
        changed['fixture_lazy.dart']='class OtherOwner { '+node['text']+' }'
        assert verify(changed),'Accepted moved late'
    mutate(state+'didChangeDependencies','subscriber is not State',lambda s:s.replace('subscribe(this,','subscribe(otherState,'))
    def reorder(text,pattern,last=False):
        calls=list(re.finditer(pattern,text));a,b=calls[-2:] if last else calls[:2]
        return text[:a.start()]+b.group()+text[a.end():b.start()]+a.group()+text[b.end():]
    mutate(state+'dispose','first two listener removals swapped',lambda s:reorder(s,r'[\w.]+\.removeListener\([\s\S]*?\);'))
    mutate(state+'dispose','last two disposals swapped',lambda s:reorder(s,r'[\w.]+\.dispose\(\);',True))
    mutate(state+'dispose','ticker after super',lambda s:s.replace('_revealCtrl.dispose();','').replace('super.dispose();','super.dispose();\n    _revealCtrl.dispose();'))
    rec_name=located(state+'_loadRecommendations')[1]['name'];enrich_name=located(state+'_loadEnrichedMeta')[1]['name']
    mutate(state+'initState','post-frame loader order',lambda s:s.replace(rec_name+'();','SWAP;').replace(enrich_name+'();',rec_name+'();').replace('SWAP;',enrich_name+'();'))
    for label,replacement in [('lost mixin','SingleTickerProviderStateMixin,\n        RouteAware'),('reordered mixin','RouteAware,\n        SingleTickerProviderStateMixin,\n        MetadataPresentationMixin<CatalogItemDetailScreen>')]:
        changed=dict(sources);changed[source]=re.sub(r'SingleTickerProviderStateMixin,\s*RouteAware,\s*MetadataPresentationMixin<CatalogItemDetailScreen>',replacement,sources[source],count=1)
        assert changed[source]!=sources[source] and verify(changed),label
    for spec in config['catalog_live_reads']:
        for wrong in ['_item.'+spec['getter'],'otherWidget.'+spec['getter']]:
            mutate(spec['member'],'host live receiver '+spec['getter'],lambda text,spec=spec,wrong=wrong:text.replace('widget.'+spec['getter'],wrong,1).replace('_deps.'+spec['getter']+'()',wrong,1))
    mutate(state+'_boundKey','bound key uses presented item',lambda s:s.replace('widget.item','_item').replace('_deps.item()','_deps.presentedItem()'))
    mutate(state+'_openMetadataRecommendation','dropped interleaved comment',lambda s:s.replace('  /// "Watch Next" recommendations. null = not yet loaded / still loading;\n','').replace('/// "Watch Next" recommendations. null = not yet loaded / still loading;\n',''))
    mutate(state+'_openMetadataRecommendation','reworded comment',lambda s:s.replace('Watch Next','Watch Later',1))
    for member in ['_simklStatus','_loadSimklStatus','_playPrimary']:
        key,node=located(state+member);changed=dict(sources);changed[key[0]]=sources[key[0]][:node['start']]+sources[key[0]][node['end']:];changed['fixture_split.dart']='class SplitOwner { '+node['text']+' }'
        assert verify(changed),'Accepted split private Simkl library'
    print('Catalog real-config positive and per-site callback/receiver/live-read, deletion, lifecycle, lazy, mixin, co-location and comment negatives: PASS')


if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--parser-package',type=Path,required=True);self_test(p.parse_args().parser_package)
