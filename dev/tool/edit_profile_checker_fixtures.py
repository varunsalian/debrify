"""Original and non-compiling syntax layouts for real-config guard fixtures.

This is a scanner/ownership fixture, never the step-0b compiling composition.
"""
import csv,json,subprocess
from collections import defaultdict


def inputs(package):
    from check_verbatim_moves import ROOT,parse,original_leaves,split_names
    config=json.loads((ROOT/'dev/tool/edit_profile_checker_config.json').read_text())
    rows=list(csv.DictReader((ROOT/'dev/tool/edit_profile_manifest.tsv').open(),delimiter='\t'))
    original=subprocess.check_output(['git','show',config['baseline']+':'+config['source']],cwd=ROOT,text=True)
    leaves=original_leaves(parse({'original':original},package,occurrence_bindings=True)['original']['declarations'],split_names(rows))
    return original,rows,config,leaves


def moved_body(row,node,rows,config):
    from registered_occurrence_substitutions import rewrite
    mapping={r['original_name'].split('.')[-1]:r for r in rows}
    edits={}
    for o in node.get('occurrences',[]):
        if o['kind']!='lexical' or o['binding']!='unbound':continue
        target=mapping.get(o['name'])
        value=None
        if target and target['original_name'].startswith('_EditProfileScreenState.') and target['destination_file']!=config['source']:
            path=next(p for p,c in config['receiver_paths'].items() if c==target['destination_class'])
            value=path+'.'+target['new_name']
        elif node['owner']=='_EditProfileScreenState' and row['destination_file']!=config['source']:
            if o['name'] in ['context','mounted']:value='_deps.'+o['name']+'()'
            elif o['name']=='setState':value='_deps.setState'
        if value:
            offset=o['offset'];size=len(o['name'])
            if node['text'][offset-node['start']-1:offset-node['start']]=='$':offset-=1;size+=1;value='${'+value+'}'
            edits[offset]=(size,value)
    old=row['original_name'].split('.')[-1]
    if old!=row['new_name']:
        t=next(t for t in node['tokens'] if not t['comment'] and t['text']==old)
        edits[t['offset']]=(len(old),row['new_name'])
    # Combine original-offset dependency and owner rewrites in one pass.
    dependencies=rewrite(node,config['registered_occurrence_substitutions']) if row['destination_file']!=config['source'] and node['owner']=='_EditProfileScreenState' else node['text']
    # Dependency rewrites change offsets: apply their original token spans too.
    if dependencies!=node['text']:
        specs=config['registered_occurrence_substitutions'];values=[t['text'] for t in node['tokens']]
        for o in node.get('occurrences',[]):
            i=o['tokenIndex']
            if o['kind']!='lexical' or o['binding']!='unbound':continue
            s=next((s for s in specs if values[i:i+len(s['before'])]==s['before']),None)
            if s:
                end=node['tokens'][i+len(s['before'])-1]['offset']+len(s['before'][-1])
                edits[o['offset']]=(end-o['offset'],''.join(s['after']))
    text=node['text']
    for at,(size,value) in sorted(edits.items(),reverse=True):
        i=at-node['start'];text=text[:i]+value+text[i+size:]
    if old=='build':text=text.replace('@override\n','',1)
    return text


def layout(original,rows,config,leaves):
    groups=defaultdict(list);edits={}
    for row in rows:
        node=leaves[row['original_name']]
        if row['destination_file']==config['source']:
            if node['owner']=='_EditProfileScreenState':edits[node['start']]=(node['end'],moved_body(row,node,rows,config))
            continue
        edits[node['start']]=(node['end'],'')
        groups[row['destination_file'],row['destination_class']].append(moved_body(row,node,rows,config))
        if row['original_name']=='_EditProfileScreenState.build':
            edits[node['start']]=(node['end'],'@override\n  Widget build(BuildContext context) => _sections.phone.build(context);')
    facade=original
    for at,(end,text) in sorted(edits.items(),reverse=True):facade=facade[:at]+text+facade[end:]
    sources={config['source']:facade}
    for (file,owner),bodies in groups.items():
        text='\n'.join(bodies)
        sources[file]=('class '+owner+' {\n'+text+'\n}\n') if owner else text+'\n'
    return sources
