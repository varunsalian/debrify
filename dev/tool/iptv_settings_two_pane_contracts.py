"""Step-aware IPTV destinations and exact composition/callback contracts."""
import json,re
from pathlib import Path
from check_verbatim_moves import ROOT,parse,ensure_parser_package
from check_settings_moves import all_nodes,tokens
from torbox_callback_identity import arguments,callback_argument

def validate_sources(sources):
 errors=[]
 for path,text in sources.items():
  if path.startswith('lib/features/iptv_settings_two_pane/'):
   if re.search(r"\b(?:import|export)\s+['\"][^'\"]*(?:/settings/iptv_settings_two_pane\.dart)['\"]",text):
    errors.append('IPTV two-pane feature must not import its facade: '+path)
 return errors

def validate_with_context(sources,config,rows):
 package=ROOT/'.dart_tool/iptv_settings_two_pane_parser/contracts/.dart_tool/package_config.json'
 ensure_parser_package(package.parent.parent,package)
 parsed=parse(sources,package,occurrence_bindings=True);lookup=all_nodes(parsed)
 source=config['source'];step=config['completed_step'];errors=[]
 allowed_files={r['destination_file'] for r in rows}|set(config['scaffold_file_steps'])
 for row in rows:
  owner,_,name=row['original_name'].rpartition('.')
  old=(source,owner,name or row['original_name']);target=(row['destination_file'],row['destination_class'],row['new_name'])
  if int(row['step'])<=step:
   if target not in lookup:errors.append('Activated destination missing: '+row['original_name'])
   if old in lookup:errors.append('Moved row remains in facade: '+row['original_name'])
  elif old not in lookup:errors.append('Future row must remain in facade: '+row['original_name'])
 for path in {r['destination_file'] for r in rows if int(r['step'])<=step}|{p for p,s in config['scaffold_file_steps'].items() if s<=step}:
  if path not in sources:errors.append('Activated destination file missing: '+path)
 for path,text in sources.items():
  if path.startswith(config['feature']+'/') and path not in allowed_files:errors.append('Unregistered IPTV two-pane file: '+path)
  if path not in config['plain_owner_files']:continue
  for (file,owner,name),node in lookup.items():
   if file!=path:continue
   # A plain section's constructor may bind this._deps; State-style access
   # in its methods/getters remains forbidden.
   if node['kind'] not in ['ClassDeclarationImpl','ConstructorDeclarationImpl'] and any(value in ['mounted','setState','this'] for value in tokens(node)):
    errors.append('Inherited State access in section: '+path+' '+name)
   for o in node.get('occurrences',[]):
    if o['name'] in ['mounted','setState','this','context'] and o['kind']=='lexical' and o['binding']=='unbound':
     errors.append('Inherited State access in section: '+path+' '+name+' '+o['name'])
 for path,owner in config['plain_owner_files'].items():
  if path not in sources:continue
  node=lookup.get((path,'',owner));values=tokens(node) if node else []
  if not values or values[:values.index('{')+1]!=['class',owner,'{']:errors.append('Section must remain a plain bound owner: '+owner)
 # This public declaration moves, so the facade-only shared registration is
 # intentionally unused. The exact original bytes are checked at its owner.
 row=next(r for r in rows if r['original_name']=='IptvSettingsTwoPane')
 key=(row['destination_file'],'',row['new_name']) if step>=2 else (source,'','IptvSettingsTwoPane')
 reference=json.loads((ROOT/'test/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_original_bodies.json').read_text())['IptvSettingsTwoPane']
 if key not in lookup or lookup[key]['text']!=reference:errors.append('Public widget declaration bytes changed at destination')
 if step>=2:
  expected=[('package:debrify/features/iptv_settings_two_pane/presentation/iptv_auto_refresh_dialog.dart',{'IptvAutoRefreshDialog','iptvAutoRefreshExplanation','iptvAutoRefreshLabel'}),('package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_widget.dart',{'IptvSettingsTwoPane','IptvSettingsTwoPaneState'})]
  text=sources.get(source,'');actual=[]
  for m in re.finditer(r"export\s+'([^']+)'\s+show\s+([^;]+);",text):actual.append((m[1],set(re.findall(r'\w+',m[2]))))
  remaining=re.sub(r"export\s+'([^']+)'\s+show\s+([^;]+);",'',text)
  remaining=re.sub(r'//[^\n]*|/\*.*?\*/','',remaining,flags=re.S)
  if actual!=expected or remaining.strip():errors.append('Facade must export exactly five names from registered destinations')
 errors.extend(callback_errors(lookup,config,rows))
 return errors

def callback_errors(lookup,config,rows):
 source=config['source'];step=config['completed_step'];errors=[]
 by_original={r['original_name']:r for r in rows}
 for ordinal,spec in enumerate(json.loads((ROOT/config['sidecars']['callbacks']).read_text())['sites']):
  try:
   owner,_,name=spec['member'].rpartition('.');row=by_original.get(spec['member'])
   if row:target=(row['destination_file'],row['destination_class'],row['new_name'])
   else:
    row=by_original[owner];target=(row['destination_file'],row['new_name'],name)
   node=lookup[target] if int(row['step'])<=step else lookup[(source,owner,name)]
   values=[v for v in tokens(node) if not v.startswith(('//','/*'))]
   call=spec['call'] if step<1 else config['callback_call_aliases'].get(spec['call'],spec['call'])
   calls=arguments(values,call);actual=callback_argument(calls[spec['occurrence']],spec)
   expected=spec['expression'] if step==0 else spec['step1_expression'] if step==1 else spec['destination_expression']
   if len(calls)!=spec['count'] or actual!=expected:errors.append('Exact callback expression changed: '+str(ordinal)+' '+spec['member'])
  except (KeyError,IndexError,ValueError):errors.append('Missing callback expression: '+str(ordinal)+' '+spec['member'])
 return errors
