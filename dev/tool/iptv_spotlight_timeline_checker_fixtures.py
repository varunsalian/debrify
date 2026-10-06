"""Real manifest layouts, built in memory; application files are never edited."""
import csv,json,posixpath,re,subprocess
from collections import defaultdict
from pathlib import Path
from check_verbatim_moves import ROOT,parse,original_leaves,split_names
SOURCE='lib/widgets/iptv/spotlight/spotlight_live_timeline.dart'
PREFIX='lib/features/iptv_spotlight_timeline/presentation/'
BRIDGE=PREFIX+'legacy_iptv_spotlight_timeline/'
STATE='_SpotlightLiveTimelineState'
FIELDS=['_ownedFocusNode','_nowFocusNode','_verticalController','_guides','_pendingLoads','_windowStart','_followNow','_lastGuideRefreshAt','_viewportSettle','_clockTick','_pointerSettle','_requestGeneration','_viewportHeight','_cursorRow','_cursorLane','_selectedProgrammeStartMs','_cursorTimeMs','_hasFocus','_lastTappedCell']
GROUPS={
 'loading':['_rowHeight','_entryAt','_onViewportMoved','_armViewportLoad','_visibleRange','_loadVisibleRows','_evictDistantRows','_loadSchedule','_removePendingIfCurrent','_accepts','_retry','_hasGuideError','_programmesForRow'],
 'window':['_guideRefreshInterval','_defaultWindowStart','_onClockTick','_ensureProgrammeVisible','_handlePointerSignal','_panTimeline','_onNowKeyEvent','_jumpToNow'],
 'cursor':['_onFocusChange','_onKeyEvent','_moveVertical','_moveHorizontal','_nearestProgramme','_distanceToProgramme','_selectProgrammeValue','_reconcileProgrammeCursor','_revealRow','_activateCursor','_activateIdentity'],
 'selection':['_focusNode','_restoreFocus','_tapIdentity','_tapProgramme','_focusFirstChannel','_focusChannelAt','_focusChannel','_selectIdentity','_selectProgramme','_announceSelection','_armPointerSelection','_cancelPointerSelection'],
 'frame':['build','_buildRuler','_buildEmpty','_buildPlayhead','_dayHeading','_weekday'],
 'rows':['_buildRow','_buildIdentity'],
 'track':['_rulerMarks','_timeX','_buildProgrammeTrack','_buildProgrammeCell','itemCanFitBadge','_formatTime'],
}
CLASSES={g:'SpotlightTimeline'+{'loading':'GuideLoading','selection':'SelectionActions'}.get(g,g.title()) for g in GROUPS}
TYPES={'_CursorLane':'SpotlightTimelineCursorLane','_GuideStatus':'SpotlightTimelineGuideStatus','_GuideSnapshot':'SpotlightTimelineGuideSnapshot','_LoadToken':'SpotlightTimelineLoadToken','_RulerMark':'SpotlightTimelineRulerMark','_GuideMessage':'SpotlightTimelineGuideMessage','_ChannelMark':'SpotlightTimelineChannelMark'}
ENTRY=['SpotlightScheduleLoader','SpotlightChannelActivate','SpotlightProgrammeActivate','SpotlightTimelineEntryKey','SpotlightTimelineEntry','SpotlightTimelineSelection']
GEOMETRY=['SpotlightProgrammeGeometry','spotlightProgrammeGeometry','spotlightRulerMarks']
LIFECYCLE=['didChangeDependencies','initState','didUpdateWidget','dispose']
FORWARDERS=['_hasFocus','_restoreFocus','_focusFirstChannel','_focusChannelAt','_focusChannel','build']

def inputs(package):
 config=json.loads((ROOT/'dev/tool/iptv_spotlight_timeline_checker_config.json').read_text())
 rows=list(csv.DictReader((ROOT/'dev/tool/iptv_spotlight_timeline_manifest.tsv').open(),delimiter='\t'))
 original=subprocess.check_output(['git','show',config['baseline']+':'+SOURCE],cwd=ROOT,text=True)
 parsed=parse({'<original>':original},package,occurrence_bindings=True)['<original>']
 return original,rows,config,parsed,original_leaves(parsed['declarations'],split_names(rows))

def view_properties(parsed):
 widget=next(d for d in parsed['declarations'] if d['name']=='SpotlightLiveTimeline')
 moved_names=set(GROUPS[g][i] for g in GROUPS for i in range(len(GROUPS[g])))
 state=next(d for d in parsed['declarations'] if d['name']==STATE)
 used={o['name'] for n in state['members'] if n['name'] in moved_names for o in n['occurrences'] if o['kind']=='selector' and o['qualifierTokens']==['widget']}
 result=[]
 for n in widget['members']:
  if not n['variables']:continue
  name=n['variables'][0]['name']
  if name not in used:continue
  first=next(t for t in n['tokens'] if not t['comment'] and t['text']=='final')
  code=n['text'][first['offset']-n['start']:]
  result.append((name,code[len('final '):code.rindex(name)].strip()))
 assert len(result)==21,result
 return result

def scaffolding(view,uses):
 owner='SpotlightTimelineOwners';sections='SpotlightTimelineSections';deps='SpotlightTimelineDependencies';viewtype='SpotlightTimelineWidgetView'
 data={BRIDGE+'spotlight_timeline_widget_view.dart':'abstract class '+viewtype+' {\n'+''.join(t+' get '+n+';\n' for n,t in view)+'}\n',
 BRIDGE+'spotlight_timeline_dependencies.dart':f'''class {deps} {{
 final {viewtype} view;
 final {owner} owners;
 final BuildContext Function() context;
 final bool Function() mounted;
 final void Function(VoidCallback) setState;
 final TvHoldOk Function() holdOk;
 final {sections} Function() sections;
 {deps}({{required this.view, required this.owners, required this.context, required this.mounted, required this.setState, required this.holdOk, required this.sections}});
}}
''',
 BRIDGE+'spotlight_timeline_sections.dart':'class '+sections+' {\n'+''.join('late final '+CLASSES[g]+' '+g+';\n' for g in GROUPS)+sections+'('+deps+' deps) {\n'+''.join(g+' = '+CLASSES[g]+'(deps);\n' for g in GROUPS)+'}\n}\n'}
 composition=f'''final _owners = {owner}();
 {sections}? _sectionsCache;
 {sections} get _sections => _sectionsCache ??= {sections}({deps}(
 view: this, owners: _owners, context: () => context, mounted: () => mounted,
 setState: setState, holdOk: () => _holdOk, sections: () => _sections));
'''
 getters=''.join('@override '+t+' get '+n+' => widget.'+n+';\n' for n,t in view)
 scaffolds={}
 for g in GROUPS:
  text=f'final {deps} _deps;\n{CLASSES[g]}(this._deps);\n'
  for name,typ,target in [('widget',viewtype,'view'),('_owners',owner,'owners'),('_sections',sections,'sections()')]:
   if name in uses[g]:text+=f'{typ} get {name} => _deps.{target};\n'
  scaffolds[g]=text
 return data,composition,getters,scaffolds

def moved_body(node,row,rows,config,step):
 by_old={r['original_name'].split('.')[-1]:r for r in rows}
 owner=node['owner'];dest=row['destination_class'];edits={}
 moved=lambda r:r['destination_file']!=SOURCE and int(r['step'])<=step
 for occ in node.get('occurrences',[]):
  if occ['kind']!='lexical' or occ['binding']!='unbound':continue
  name=occ['name'];target=by_old.get(name);value=name
  if owner==STATE and target and target['original_name'].startswith(STATE+'.') and moved(target):
   value=target['new_name']
   if target['destination_class']!=dest:
    paths=[p for p,c in config['receiver_owners'].items() if c==target['destination_class']]
    path=next(p for p in paths if p=='SpotlightTimelineTrack') if name=='_formatTime' else paths[0]
    value=path+'.'+value
  elif owner==STATE and moved(row) and name in ['context','mounted','setState']:
   value='_deps.'+name+('()' if name!='setState' else '')
  elif owner==STATE and moved(row) and name=='_holdOk':value='_deps.holdOk()'
  if value!=name:edits[occ['offset']]=(len(name),value)
 for t in node['tokens']:
  if t['comment']:continue
  name=t['text']
  if name in TYPES:
   target=by_old.get(name)
   if step >= int(target['step']):edits[t['offset']]=(len(name),TYPES[name])
 old=row['original_name'].split('.')[-1]
 if old!=row['new_name'] and moved(row):
  token=next(t for t in node['tokens'] if not t['comment'] and t['text']==old)
  edits[token['offset']]=(len(old),row['new_name'])
 text=node['text']
 for offset,(length,value) in sorted(edits.items(),reverse=True):
  i=offset-node['start'];text=text[:i]+value+text[i+length:]
 if row['original_name']==STATE+'.build' and step>=2:text=text.replace('@override\n','',1)
 # Identifier links follow manifest names; prose is copied exactly.
 for old,new in {r['original_name'].split('.')[-1]:r['new_name'] for r in rows}.items():
  text=text.replace('['+old+']','['+new+']')
 return text

def layout(original,rows,config,parsed,leaves,step):
 if step==0:return {SOURCE:original}
 by_name={r['original_name']:r for r in rows}
 imports=original[:parsed['declarations'][0]['start']]
 imports=re.sub(r"import '([^']+)'",lambda m:m.group() if m[1].startswith(('dart:','package:')) else "import 'package:debrify/"+posixpath.normpath(posixpath.join(posixpath.dirname(SOURCE),m[1])).removeprefix('lib/')+"'",imports)
 destinations=defaultdict(list);facade=[];last=parsed['declarations'][0]['start']
 uses={g:set() for g in GROUPS}
 for g in GROUPS:
  for name in GROUPS[g]:
   row=by_name[STATE+'.'+name];text=moved_body(leaves[STATE+'.'+name],row,rows,config,2)
   for value in ['widget','_owners','_sections']:
    if re.search(r'\b'+value+r'\.',text):uses[g].add(value)
 scaffold_data,composition,getters,section_scaffolds=scaffolding(view_properties(parsed),uses)
 for d in parsed['declarations']:
  leading=original[last:d['start']];last=d['end']
  if d['name']!=STATE:
   row=by_name[d['name']];text=leading+moved_body(d,row,rows,config,step)
   if int(row['step'])<=step and row['destination_file']!=SOURCE:destinations[row['destination_file']].append(text)
   else:facade.append(text)
   continue
  if step<2:
   facade.append(leading+moved_body(d,{'original_name':STATE,'new_name':STATE,'destination_file':SOURCE,'destination_class':STATE},rows,config,step));continue
  groups=defaultdict(list);prior=original.index('{',d['offset'])+1
  for n in d['members']:
   row=by_name[STATE+'.'+n['name']]
   text=original[prior:n['start']]+moved_body(n,row,rows,config,step);prior=n['end']
   groups[(row['destination_file'],row['destination_class'])].append(text)
  for (path,cls),bodies in groups.items():
   header='class '+cls+' {';extra='';tail=''
   if cls==STATE:
    header='class '+STATE+' extends State<SpotlightLiveTimeline> implements SpotlightTimelineWidgetView {';extra=composition;tail=getters
    for name in FORWARDERS:tail+=config['forwarders'][STATE+'.'+name]['text']+'\n'
   elif cls not in ['SpotlightTimelineOwners','SpotlightTimelinePalette']:
    extra=section_scaffolds[next(g for g in GROUPS if cls==CLASSES[g])]
   text=leading+header+'\n'+extra+'\n'.join(bodies)+tail+'\n}\n';leading=''
   if path==SOURCE:facade.append(text)
   else:destinations[path].append(text)
 if step>=2:
  for path,text in scaffold_data.items():destinations[path].append(text)
 all_files=[SOURCE,*destinations]
 def file_imports(path):
  return imports+''.join("import 'package:debrify/"+p[len('lib/'):] +"';\n" for p in all_files if p!=path and p!=SOURCE)
 exports="export 'package:debrify/"+(BRIDGE+'spotlight_timeline_entry.dart')[len('lib/'):]+"' show "+', '.join(ENTRY)+";\n"
 if step>=2:exports+="export 'package:debrify/"+(BRIDGE+'spotlight_timeline_track.dart')[len('lib/'):]+"' show "+', '.join(GEOMETRY)+";\n"
 sources={SOURCE:file_imports(SOURCE)+exports+'\n'.join(facade)+'\n'}
 sources.update({p:file_imports(p)+'\n'.join(b) for p,b in destinations.items()})
 return sources
