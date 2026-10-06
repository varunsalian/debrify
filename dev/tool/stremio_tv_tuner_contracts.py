"""Mandatory step-aware tuner ownership; no cached validation decisions."""
import json,re
from pathlib import Path
from check_verbatim_moves import ROOT,ensure_parser_package,parse
from check_settings_moves import all_nodes,normalize,tokens
from torbox_callback_identity import arguments,callback_argument

def validate_sources(sources):
 return []

def validate_with_context(sources,config,rows):
 package=ROOT/'.dart_tool/stremio_tv_tuner_parser/contracts'
 package_config=package/'.dart_tool/package_config.json'
 ensure_parser_package(package,package_config)
 lookup=all_nodes(parse(sources,package_config,occurrence_bindings=True))
 source=config['source'];step=config['completed_step'];errors=[]
 for row in rows:
  owner,_,name=row['original_name'].rpartition('.')
  old=(source,owner,name or row['original_name'])
  target=(row['destination_file'],row['destination_class'],row['new_name'])
  if target[0]==source:
   if target not in lookup:errors.append('Retained row must stay in facade: '+row['original_name'])
  elif int(row['step'])<=step:
   if owner == '_StremioTvTunerState' and target in lookup:
    for occurrence in lookup[target].get('occurrences', []):
     if (occurrence['name'] in ['context', 'mounted', 'setState']
         and occurrence['kind'] == 'lexical' and occurrence['binding'] == 'unbound'):
      errors.append('Bare tuner State access in moved section: '+row['original_name']+' '+occurrence['name'])
   if target not in lookup:errors.append('Activated destination missing: '+row['original_name'])
   if old in lookup and row['original_name'] not in config.get('forwarders',{}):
    errors.append('Moved row remains in facade: '+row['original_name'])
   if row['original_name'] in config.get('forwarders',{}) and old not in lookup:
    errors.append('Registered forwarder missing: '+row['original_name'])
  elif old not in lookup:
   errors.append('Future row must remain in facade: '+row['original_name'])
 active_files={r['destination_file'] for r in rows if int(r['step'])<=step}
 active_files.update(p for p,s in config['scaffold_file_steps'].items() if s<=step)
 for path in sorted(active_files-sources.keys()):errors.append('Activated destination file missing: '+path)
 allowed_files={r['destination_file'] for r in rows}|set(config['scaffold_file_steps'])
 for path,text in sources.items():
  if path.startswith(config['feature']+'/'):
   if re.search(r"\b(?:import|export)\s+['\"][^'\"]*stremio_tv_tuner\.dart['\"]",text):
    errors.append('Tuner feature must not import its facade: '+path)
   if not path.endswith('/stremio_tv_tuner_stage_content.dart'):
    for (file,owner,name),node in lookup.items():
     if file!=path:continue
     if any(o['kind']=='selector' and o['qualifierTokens'][:1]==['stageState'] for o in node.get('occurrences', [])):
      errors.append('stageState receiver outside content owner: '+path)
  if path.startswith(config['feature']+'/') and path not in allowed_files:errors.append('Unregistered tuner file: '+path)
 for path,owner in config.get('plain_owner_files',{}).items():
  if path not in sources:continue
  node=lookup.get((path,'',owner))
  values=[t['text'] for t in node['tokens'] if not t['comment']] if node else []
  if not values or values[:values.index('{')+1]!=['class',owner,'{']:
   errors.append('Tuner section must remain a plain bound owner: '+owner)
 by_original={row['original_name']:row for row in rows}
 for ordinal,spec in enumerate(json.loads((ROOT/config['sidecars']['callbacks']).read_text())['sites']):
  try:
   owner,_,name=spec['member'].rpartition('.')
   row=by_original.get(spec['member'])
   if row:
    target=(row['destination_file'],row['destination_class'],row['new_name'])
   else:
    row=by_original[owner];target=(row['destination_file'],row['new_name'],name)
   node=lookup.get(target) or lookup.get((source,owner,name)) or lookup[(source,config.get('type_renames',{}).get(owner,owner),name)]
   values=[v for v in tokens(node) if not v.startswith(('//','/*'))]
   calls=arguments(values,spec['call']) or arguments(values,config.get('callback_call_aliases',{}).get(spec['call'],spec['call']))
   actual=callback_argument(calls[spec['occurrence']],spec)
   if len(calls)!=spec['count'] or normalize(actual,rows,row)!=normalize(spec['expression'],rows,row):
    errors.append('Original tuner callback expression changed: '+str(ordinal)+' '+spec['member'])
  except (KeyError,IndexError,ValueError):
   errors.append('Missing tuner callback expression: '+str(ordinal)+' '+spec['member'])
 return errors
