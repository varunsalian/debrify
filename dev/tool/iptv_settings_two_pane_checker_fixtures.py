"""Real original bodies in the frozen step schedule; also used by lint probes."""
import csv,json,posixpath,re,subprocess
from collections import defaultdict
from check_verbatim_moves import ROOT,parse,original_leaves,split_names
SOURCE='lib/screens/settings/iptv_settings_two_pane.dart'
PREFIX='lib/features/iptv_settings_two_pane/presentation/'
BRIDGE=PREFIX+'legacy_iptv_settings_two_pane/'
STATE='IptvSettingsTwoPaneState'
INVENTORY=json.loads((ROOT/'dev/tool/iptv_settings_two_pane_inventory.json').read_text())
GROUPS=INVENTORY['groups'];FIELDS=INVENTORY['fields'];CLASSES=INVENTORY['classes'];TYPES=INVENTORY['types']
MEMBERS={g:g.split('_')[0]+''.join(p.title() for p in g.split('_')[1:]) for g in GROUPS}

def inputs(package):
 config=json.loads((ROOT/'dev/tool/iptv_settings_two_pane_checker_config.json').read_text())
 rows=list(csv.DictReader((ROOT/'dev/tool/iptv_settings_two_pane_manifest.tsv').open(),delimiter='\t'))
 original=subprocess.check_output(['git','show',config['baseline']+':'+SOURCE],cwd=ROOT,text=True)
 parsed=parse({'<original>':original},package,occurrence_bindings=True)['<original>']
 return original,rows,config,parsed,original_leaves(parsed['declarations'],split_names(rows))

def scaffolding():
 deps='IptvSettingsTwoPaneDependencies';owner='IptvSettingsTwoPaneOwners';sections='IptvSettingsTwoPaneSections'
 composition=f'''final _owners = {owner}();
 {sections}? _sectionsCache;
 {sections} get _sections => _sectionsCache ??= {sections}({deps}(
 widget: () => widget, context: () => context, owners: _owners,
 sections: () => _sections));
'''
 data={BRIDGE+'iptv_settings_two_pane_dependencies.dart':f'''class {deps} {{
 final IptvSettingsTwoPane Function() widget;
 final BuildContext Function() context;
 final {owner} owners;
 final {sections} Function() sections;
 {deps}({{required this.widget, required this.context, required this.owners, required this.sections}});
}}
class {sections} {{
'''+''.join(f'late final {c} {MEMBERS[g]};\n' for g,c in CLASSES.items())+f'{sections}({deps} deps) {{\n'+''.join(f'{MEMBERS[g]} = {c}(deps);\n' for g,c in CLASSES.items())+'}\n}\n'}
 extras={}
 for g,c in CLASSES.items():
  text=f'final {deps} _deps;\n{c}(this._deps);\nIptvSettingsTwoPane get widget => _deps.widget();\n'
  if g in ['navigation','rail','panes']:text+=f'{owner} get _owners => _deps.owners;\n'
  if g!='navigation':text+=f'{sections} get _sections => _deps.sections();\n'
  extras[g]=text
 return data,composition,extras

def moved_body(node,row,rows,config,step):
 by_old={r['original_name'].split('.')[-1]:r for r in rows};edits={};owner=node['owner'];dest=row['destination_class']
 for occ in node.get('occurrences',[]):
  if occ['kind']!='lexical' or occ['binding']!='unbound':continue
  name=occ['name'];target=by_old.get(name);value=name
  if owner==STATE and target and target['original_name'].startswith(STATE+'.') and int(target['step'])<=step:
   value=target['new_name']
   if target['destination_class']!=dest:
    value=next(p for p,c in config['receiver_owners'].items() if c==target['destination_class'])+'.'+value
  elif owner==STATE and int(row['step'])<=step and dest!=STATE and name=='context':value='_deps.context()'
  if value!=name:edits[occ['offset']]=(len(name),value)
 for t in node['tokens']:
  if t['comment']:continue
  name=t['text'];target=by_old.get(name)
  if name in TYPES and step>=int(target['step']):edits[t['offset']]=(len(name),TYPES[name])
 old=row['original_name'].split('.')[-1]
 if old!=row['new_name'] and int(row['step'])<=step:
  token=next(t for t in node['tokens'] if not t['comment'] and t['text']==old)
  edits[token['offset']]=(len(old),row['new_name'])
 text=node['text']
 for offset,(length,value) in sorted(edits.items(),reverse=True):
  i=offset-node['start'];text=text[:i]+value+text[i+length:]
 return text

COMMON=['package:flutter/material.dart']
MODEL=['package:debrify/models/iptv_playlist.dart']
THEME=['package:debrify/theme/app_theme_scope.dart']
STATS='package:debrify/services/iptv_source_stats.dart'
STARTUP='package:debrify/services/storage/startup_iptv_storage.dart'
MEDIA='package:debrify/services/iptv_media_store.dart'
APPEARANCE='package:debrify/services/storage/iptv_appearance_storage.dart'
STYLE='package:debrify/screens/settings/iptv_style_page.dart'
def imports_for(path,step):
 def local(name):return 'package:debrify/'+PREFIX[4:]+name+'.dart'
 def bridge(name):return 'package:debrify/'+BRIDGE[4:]+'iptv_settings_two_pane_'+name+'.dart'
 pieces={
 'dialog':local('iptv_auto_refresh_dialog'),'dest':local('iptv_two_pane_destination'),
 'rail_entry':local('iptv_two_pane_rail_entry'),'parts':local('iptv_two_pane_pane_parts'),
 'row':local('iptv_two_pane_row'),'method':local('iptv_two_pane_method_card')}
 base=COMMON[:];show={}
 if path==SOURCE and step<2:
  base+=['package:flutter/services.dart',*MODEL,*THEME,'package:debrify/theme/app_theme.dart',STATS,MEDIA,STARTUP,APPEARANCE,STYLE]
  if step:base+=[*pieces.values()];base.remove('package:flutter/services.dart')
 elif path.endswith('iptv_auto_refresh_dialog.dart'):pass
 elif path.endswith('iptv_two_pane_destination.dart'):base=[]
 elif '/legacy_' not in path:base+=THEME+(['package:flutter/services.dart'] if path.endswith(('rail_entry.dart','row.dart','method_card.dart')) else [])
 else:
  group=path.rsplit('iptv_settings_two_pane_',1)[1][:-5]
  if group=='widget':
   base+=MODEL+THEME+[MEDIA,APPEARANCE,pieces['dest'],bridge('owners'),bridge('dependencies')]
   show={MEDIA:'IptvListMeta',APPEARANCE:'IptvAppearanceStorage'}
  elif group=='owners':base+=['package:debrify/theme/app_theme.dart',STATS,pieces['dest']];show={STATS:'IptvSourceStats'}
  elif group=='dependencies':base+=[bridge('widget'),bridge('owners'),*[bridge(g) for g in GROUPS]]
  else:
   base+=[bridge('dependencies'),bridge('widget')]
   if group in ['navigation','rail','panes']:base+=[bridge('owners')]
   if group=='navigation':base+=[STATS,pieces['dest']];show={STATS:'IptvSourceStatsLoader'}
   elif group=='rail':base+=MODEL+[STATS,STARTUP,STYLE,pieces['dest'],pieces['rail_entry'],pieces['dialog']];show={pieces['dialog']:'iptvAutoRefreshLabel',STATS:'IptvSourceStatsLoader',STARTUP:'StartupIptvStorage',STYLE:'iptvStyleLabel'}
   elif group=='panes':base+=MODEL+[STATS,pieces['dest'],pieces['parts'],pieces['row'],pieces['method'],pieces['dialog']];show={STATS:'IptvGuideSource, IptvSourceStats, IptvSourceStatsLoader'}
   elif group=='list_panes':base+=[STARTUP,pieces['parts'],pieces['row']];show={STARTUP:'StartupIptvStorage'}
   elif group=='preference_panes':base+=[STYLE,pieces['parts'],pieces['row']];show={STYLE:'kIptvStyleChoices'}
 return ''.join("import '"+p+"'"+(' show '+show[p] if p in show else '')+';\n' for p in sorted(set(base)))

def auto_refresh_export():
 return "export 'package:debrify/"+PREFIX[4:]+"iptv_auto_refresh_dialog.dart'\n    show IptvAutoRefreshDialog, iptvAutoRefreshExplanation, iptvAutoRefreshLabel;\n"

def exports():
 return auto_refresh_export()+"export 'package:debrify/"+BRIDGE[4:]+"iptv_settings_two_pane_widget.dart'\n    show IptvSettingsTwoPane, IptvSettingsTwoPaneState;\n"

def layout(original,rows,config,parsed,leaves,step):
 if step==0:return {SOURCE:original}
 by_name={r['original_name']:r for r in rows};destinations=defaultdict(list);facade=[]
 scaffold_data,composition,extra=scaffolding();last=parsed['declarations'][0]['start']
 for d in parsed['declarations']:
  leading=original[last:d['start']];last=d['end']
  if d['name']!=STATE or step<2:
   row=by_name.get(d['name'],{'original_name':STATE,'new_name':STATE,'destination_class':STATE,'step':'2'})
   text=leading+moved_body(d,row,rows,config,step)
   if int(row['step'])<=step:destinations[row['destination_file']].append(text)
   else:facade.append(text)
   continue
  groups=defaultdict(list);prior=original.index('{',d['offset'])+1
  for m in d['members']:
   row=by_name[STATE+'.'+m['name']];text=original[prior:m['start']]+moved_body(m,row,rows,config,step);prior=m['end']
   groups[(row['destination_file'],row['destination_class'])].append(text)
  for (path,cls),bodies in groups.items():
   header='class '+cls+' {';scaffold=''
   if cls==STATE:header='class '+STATE+' extends State<IptvSettingsTwoPane> {';scaffold=composition
   elif cls!='IptvSettingsTwoPaneOwners':scaffold=extra[next(g for g,c in CLASSES.items() if cls==c)]
   destinations[path].append(leading+header+'\n'+scaffold+'\n'.join(bodies)+'\n}\n');leading=''
 if step>=2:
  for path,text in scaffold_data.items():destinations[path].append(text)
 sources={SOURCE:imports_for(SOURCE,step)+'\n'.join(facade)+'\n' if step<2 else exports()}
 if step==1:
  imports=imports_for(SOURCE,step);sources[SOURCE]=sources[SOURCE].replace(imports,imports+'\n'+auto_refresh_export(),1)
 sources.update({p:imports_for(p,step)+'\n'.join(b) for p,b in destinations.items()})
 return sources
