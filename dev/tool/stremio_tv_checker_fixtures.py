"""Test-only syntax layouts; compilation/composition proof belongs to step 0b."""
import csv,io,json,subprocess
from collections import defaultdict
from pathlib import Path

def inputs(package, *, original_fixture=False):
    from check_verbatim_moves import ROOT,parse,original_leaves,split_names
    config=json.loads((ROOT/'dev/tool/stremio_tv_checker_config.json').read_text())
    rows=list(csv.DictReader((ROOT/'dev/tool/stremio_tv_manifest.tsv').open(),delimiter='\t'))
    if original_fixture:
        # Keep the reviewed ORIGINAL/partial/completed fixtures frozen while
        # the real CLI validates each live intermediate ownership map.
        checkpoint='e1d4fe1f2b0462826de0a591ef7371a84200d85d'
        def frozen(path):
            return subprocess.check_output(['git','show',checkpoint+':'+path],cwd=ROOT,text=True)
        config=json.loads(frozen('dev/tool/stremio_tv_checker_config.json'))
        rows=list(csv.DictReader(io.StringIO(frozen('dev/tool/stremio_tv_manifest.tsv')),delimiter='\t'))
        sidecar=ROOT/'.dart_tool/stremio_tv_parser/frozen_fixture_scaffolding.json'
        sidecar.parent.mkdir(parents=True,exist_ok=True)
        text=frozen('dev/tool/stremio_tv_scaffolding.json')
        if not sidecar.exists() or sidecar.read_text()!=text:sidecar.write_text(text)
        config['sidecars']['scaffolding']=str(sidecar)
    original=subprocess.check_output(['git','show',config['baseline']+':'+config['source']],cwd=ROOT,text=True)
    leaves=original_leaves(parse({'<original>':original},package,occurrence_bindings=True)['<original>']['declarations'],split_names(rows))
    return original,rows,config,leaves

def moved_body(row,node,rows,config,selected=None):
    by_old={r['original_name'].split('.')[-1]:r for r in rows}
    aliases={a['original_name']:a['alias'] for a in config['planned_type_aliases']}
    edits={};is_state=node['owner']=='_StremioTvScreenState'
    moving=row['destination_file']!=config['source'] and (selected is None or row['original_name'] in selected)
    for occurrence in node.get('occurrences',[]):
        name=occurrence['name']
        if occurrence['kind']!='lexical' or occurrence['binding']!='unbound':continue
        target=by_old.get(name);replacement=name
        if target and (selected is None or target['original_name'] in selected):
            if target['original_name'].rpartition('.')[0]=='_StremioTvScreenState':
                if target['destination_file']!=config['source']:
                    paths=[p for p,c in config['receiver_paths'].items() if c==target['destination_class']]
                    path=sorted(paths,key=lambda p:(not p.startswith(('_owners.','_sections.')),len(p)))[0]
                    replacement=path+'.'+target['new_name']
            else:replacement=name if name==node['name'] and name in aliases else aliases.get(name,target['new_name'])
        elif is_state and moving:
            if name in ['context','mounted']:replacement='_deps.'+name+'()'
            elif name=='setState':replacement='_deps.setState'
        if replacement!=name:
            offset=occurrence['offset'];relative=offset-node['start']
            if '.' in replacement and node['text'][relative-1:relative]=='$':edits[offset-1]=(len(name)+1,'${'+replacement+'}')
            else:edits[offset]=(len(name),replacement)
    for token in node['tokens']:
        name=token['text'];target=by_old.get(name)
        if not token['comment'] and target and name.startswith('_') and name[1:2].isupper() and (selected is None or target['original_name'] in selected):
            replacement=name if name==node['name'] and name in aliases else aliases.get(name,target['new_name'])
            if replacement!=name:edits[token['offset']]=(len(name),replacement)
    if is_state and moving:
        values=node['tokens']
        for i in range(len(values)-2):
            if [t['text'] for t in values[i:i+3]]==['widget','.','isTelevision']:
                # Register exactly this three-token read, never picker State reads.
                edits[values[i]['offset']]=(values[i+2]['offset']+len('isTelevision')-values[i]['offset'],'_deps.isTelevision()')
    old=row['original_name'].split('.')[-1]
    if moving and old!=row['new_name']:
        token=next(t for t in node['tokens'] if not t['comment'] and t['text']==old)
        edits[token['offset']]=(len(old),row['new_name'])
    text=node['text']
    for offset,(length,replacement) in sorted(edits.items(),reverse=True):
        relative=offset-node['start'];text=text[:relative]+replacement+text[relative+length:]
    if row['original_name'] in config.get('forwarders',{}) and moving:
        text=text.replace('@override','',1)
    return text

def layout(original,rows,config,leaves,selected=None):
    selected=set(selected if selected is not None else [r['original_name'] for r in rows if r['destination_file']!=config['source']])
    replacements={};destinations=defaultdict(list)
    comments=defaultdict(list)
    for leaf in config.get('comment_leaves',[]):
        if leaf['anchor'] in selected:
            replacements[leaf['offset']]=(leaf['end_offset'],'')
            comments[leaf['anchor']].append(leaf['text'])
    for row in rows:
        name=row['original_name'];node=leaves[name]
        if name in selected and row['destination_file']!=config['source']:
            forwarder=config.get('forwarders',{}).get(name)
            replacements[node['start']]=(node['end'],'@override Widget build(BuildContext context) => _sections.layout.build(context);' if forwarder else '')
            destinations[row['destination_file'],row['destination_class']].append('\n'.join(comments[name])+'\n'+moved_body(row,node,rows,config,selected))
        elif node['owner']=='_StremioTvScreenState':replacements[node['start']]=(node['end'],moved_body(row,node,rows,config,selected))
    facade=original
    for start,(end,body) in sorted(replacements.items(),reverse=True):facade=facade[:start]+body+facade[end:]
    from check_verbatim_moves import ROOT
    scaffold_data=json.loads((ROOT/config['sidecars']['scaffolding']).read_text())
    if any(r['original_name'] in selected and r['destination_class'] in config['occurrence_field_bindings']['record_paths'].values() for r in rows):
        composition='\n'.join(' '.join(s['tokens']) for s in scaffold_data['facade_composition'])
        marker='class _StremioTvScreenState extends State<StremioTvScreen> {'
        facade=facade.replace(marker,marker+'\n'+composition,1)
    sources={config['source']:facade}
    for (path,owner),bodies in destinations.items():
        body='\n'.join(bodies)
        if any(spec['owner']==owner for spec in config.get('planned_plain_sections',[])):
            body='\n'.join(' '.join(spec['tokens']) for spec in scaffold_data['scaffolds'] if spec['file']==path and spec['owner']==owner)+'\n'+body
        sources[path]=sources.get(path,'')+('class '+owner+' {\n'+body+'\n}\n' if owner else body+'\n')
    for alias in config.get('type_aliases',[]):
        if alias['original_name'] in selected:sources[alias['file']]+='typedef '+alias['alias']+' = '+alias['original_name']+';\n'
    # D4: the compiling probe alone authorizes exact typed constructor
    # forwarders. Keep ORIGINAL untouched; add only the frozen declarations
    # when their private widget file is in this simulated layout.
    for spec in scaffold_data['scaffolds']:
        if (spec['owner']=='' and spec['file'] in sources
                and spec['file'] not in config['scaffolds']
                and spec['tokens'][:1]!=['typedef']):
            sources[spec['file']]+=' '.join(spec['tokens'])+'\n'
    return sources
