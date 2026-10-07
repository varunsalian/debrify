"""Step-aware ownership, exact exports and callback wiring for this manifest."""
import json,re
from check_verbatim_moves import ROOT,ensure_parser_package,parse
from check_settings_moves import all_nodes,normalize,tokens
from torbox_callback_identity import arguments,callback_argument
from iptv_spotlight_timeline_checker_fixtures import SOURCE,STATE,BRIDGE,ENTRY,GEOMETRY

def validate_sources(sources):
 return []

def validate_with_context(sources,config,rows):
 package=ROOT/'.dart_tool/iptv_spotlight_timeline_parser/contracts/.dart_tool/package_config.json'
 ensure_parser_package(package.parent.parent,package)
 parsed=parse(sources,package,occurrence_bindings=True);lookup=all_nodes(parsed)
 source=config['source'];step=config['completed_step'];errors=[]
 for row in rows:
  owner,_,name=row['original_name'].rpartition('.')
  old=(source,owner,name or row['original_name'])
  if old not in lookup and name in config['type_renames']:old=(source,owner,config['type_renames'][name])
  target=(row['destination_file'],row['destination_class'],row['new_name'])
  if target[0]==source:
   if target not in lookup:errors.append('Retained row must stay in facade: '+row['original_name'])
  elif int(row['step'])<=step:
   if owner==STATE and target in lookup:
    for o in lookup[target].get('occurrences',[]):
     if o['name'] in ['context','mounted','setState'] and o['kind']=='lexical' and o['binding']=='unbound':errors.append('Bare timeline State access in moved section: '+row['original_name']+' '+o['name'])
   if target not in lookup:errors.append('Activated destination missing: '+row['original_name'])
   if old in lookup and row['original_name'] not in config['forwarders']:errors.append('Moved row remains in facade: '+row['original_name'])
   if row['original_name'] in config['forwarders'] and old not in lookup:errors.append('Registered forwarder missing: '+row['original_name'])
  elif old not in lookup:errors.append('Future row must remain in facade: '+row['original_name'])
 active_files={r['destination_file'] for r in rows if int(r['step'])<=step}|{p for p,s in config['scaffold_file_steps'].items() if s<=step}
 for path in sorted(active_files-sources.keys()):errors.append('Activated destination file missing: '+path)
 allowed_files={r['destination_file'] for r in rows}|set(config['scaffold_file_steps'])
 for path,text in sources.items():
  if path.startswith(config['feature']+'/'):
   if re.search(r"\b(?:import|export)\s+['\"][^'\"]*spotlight_live_timeline\.dart['\"]",text):errors.append('Timeline feature must not import its facade: '+path)
   if path not in allowed_files:errors.append('Unregistered timeline file: '+path)
 for path,owner in config['plain_owner_files'].items():
  if path not in sources:continue
  node=lookup.get((path,'',owner));values=tokens(node) if node else []
  if not values or values[:values.index('{')+1]!=['class',owner,'{']:errors.append('Timeline section must remain a plain bound owner: '+owner)
 expected=[]
 if step>=1:expected.append((BRIDGE+'spotlight_timeline_entry.dart',ENTRY))
 if step>=2:expected.append((BRIDGE+'spotlight_timeline_track.dart',GEOMETRY))
 # Package and relative imports are equivalent; show-list names and order are exact.
 actual=[]
 for directive in parsed[source]['directives']:
  if not re.match(r'export\s',directive):continue
  match=re.fullmatch(r"export\s+['\"]([^'\"]+)['\"]\s+show\s+([\w\s,]+);",directive.strip())
  if not match:errors.append('Timeline export must use exact show list');continue
  uri,names=match.groups()
  if uri.startswith('package:debrify/'):path='lib/'+uri[len('package:debrify/'):]
  else:
   import posixpath
   path=posixpath.normpath(posixpath.join(posixpath.dirname(source),uri))
  actual.append((path,[n.strip() for n in names.split(',')]))
 if actual!=expected:errors.append('Timeline re-export show lists changed: '+repr(actual))
 by_original={r['original_name']:r for r in rows}
 for ordinal,spec in enumerate(json.loads((ROOT/config['sidecars']['callbacks']).read_text())['sites']):
  try:
   owner,_,name=spec['member'].rpartition('.')
   row=by_original.get(spec['member'])
   target=(row['destination_file'],row['destination_class'],row['new_name']) if row else (by_original[owner]['destination_file'],by_original[owner]['new_name'],name)
   node=lookup.get(target) or lookup[(source,owner,name)]
   values=[v for v in tokens(node) if not v.startswith(('//','/*'))]
   calls=arguments(values,spec['call']) or arguments(values,config['callback_call_aliases'].get(spec['call'],spec['call']))
   actual=callback_argument(calls[spec['occurrence']],spec)
   if len(calls)!=spec['count'] or normalize(actual,rows,row)!=normalize(spec['expression'],rows,row):errors.append('Original timeline callback expression changed: '+str(ordinal)+' '+spec['member'])
  except (KeyError,IndexError,ValueError):errors.append('Missing timeline callback expression: '+str(ordinal)+' '+spec['member'])
 return errors
