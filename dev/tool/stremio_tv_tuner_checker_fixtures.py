"""Real planned declaration layouts, built in memory without editing app files."""
import csv,json,subprocess,re
from pathlib import Path
from collections import defaultdict
from check_verbatim_moves import ROOT,parse,original_leaves,split_names
SOURCE='lib/screens/stremio_tv/widgets/stremio_tv_tuner.dart'
PREFIX='lib/features/stremio_tv_tuner/presentation/'
BRIDGE=PREFIX+'legacy_stremio_tv_tuner/'
STATE='_StremioTvTunerState'
STAGE='_StageState'
FIELDS=['_tick','_activeId','_centredId','_pendingId','_settle','_indexById','_pageController','_dialScroll']
GROUPS={
 'channels':['_syncTick','_rebuildIndex','_identFor','_nowPlaying','_nextPlaying','_displayProgress','_realIndex','_nodeFor','_setActive','_precacheNeighborBackdrops','_channelById','_surf'],
 'dial':['_touchDial','_onDialScroll','_snapDial','_dialItemExtent','_dialLeadingPad','_dialLeadingPadFor','_focusRealIndex','_scrollDialToIndex','_focusWhenAttached'],
 'sheets':['_openActions','_openChannelList','_channelListRow','_listThumbFallback'],
 'layout':['_buildWide','_buildNarrow'],
}
PRIVATE={'_realIndex','_precacheNeighborBackdrops','_dialItemExtent','_dialLeadingPad','_scrollDialToIndex','_focusWhenAttached','_channelListRow','_listThumbFallback'}
CONTENT=['_buildContent','_glassPill','_channelTag','_metaRow','_metaStyle','_dot','_liveBar','_upNext','_tuningState','_hiddenState']
TYPES={'_Stage':'StremioTvTunerStage','_StageState':'StremioTvTunerStageState','_StageDescription':'StremioTvTunerStageDescription','_LivePip':'StremioTvTunerLivePip','_Marquee':'StremioTvTunerMarquee','_DialCard':'StremioTvTunerDialCard','_DialCardState':'StremioTvTunerDialCardState','_DialHintChip':'StremioTvTunerDialHintChip'}

def inputs(package):
 config=json.loads((ROOT/'dev/tool/stremio_tv_tuner_checker_config.json').read_text())
 rows=list(csv.DictReader((ROOT/'dev/tool/stremio_tv_tuner_manifest.tsv').open(),delimiter='\t'))
 original=subprocess.check_output(['git','show',config['baseline']+':'+SOURCE],cwd=ROOT,text=True)
 parsed=parse({'<original>':original},package,occurrence_bindings=True)['<original>']
 return original,rows,config,parsed,original_leaves(parsed['declarations'],split_names(rows))

def scaffolding(view):
 owner='StremioTvTunerOwners'
 section='StremioTvTunerSections'
 deps='StremioTvTunerDependencies'
 viewtype='StremioTvTunerWidgetView'
 classes={g:'StremioTvTuner'+g.title() for g in GROUPS}
 data={
 BRIDGE+'stremio_tv_tuner_widget_view.dart':'abstract class '+viewtype+' {\n'+''.join(t+' get '+n+';\n' for n,t in view)+'}\n',
 BRIDGE+'stremio_tv_tuner_dependencies.dart':f'''class {deps} {{
 final {viewtype} view;
 final {owner} owners;
 final BuildContext Function() context;
 final bool Function() mounted;
 final void Function(VoidCallback) setState;
 final {section} Function() sections;
 {deps}({{required this.view, required this.owners, required this.context, required this.mounted, required this.setState, required this.sections}});
}}
''',
 BRIDGE+'stremio_tv_tuner_sections.dart':'class '+section+' {\n'+''.join('late final '+classes[g]+' '+g+';\n' for g in GROUPS)+section+'('+deps+' deps) {\n'+''.join(g+' = '+classes[g]+'(deps);\n' for g in GROUPS)+'}\n}\n',
 }
 composition=f'''final _owners = {owner}();
 {section}? _sectionsCache;
 {section} get _sections => _sectionsCache ??= {section}({deps}(
 view: this, owners: _owners, context: () => context, mounted: () => mounted,
 setState: setState, sections: () => _sections));
'''
 getters=''.join('@override '+t+' get '+n+' => widget.'+n+';\n' for n,t in view)
 section_scaffolds={}
 for g in GROUPS:
  # Reviewed dependencies: layout borrows owners for wheel/centred notifier;
  # Channels uses widget/owners; dial, sheets and layout also reach sections.
  text=f'final {deps} _deps;\n{classes[g]}(this._deps);\n{viewtype} get widget => _deps.view;\n{owner} get _owners => _deps.owners;\n'
  if g != 'channels': text += f'{section} get _sections => _deps.sections();\n'
  section_scaffolds[g]=text
 return data,composition,getters,section_scaffolds

def view_properties(parsed):
 widget=next(d for d in parsed['declarations'] if d['name']=='StremioTvTuner')
 result=[]
 for node in widget['members']:
  if not node['variables']:continue
  name=node['variables'][0]['name']
  if name=='controller':continue
  first=next(t for t in node['tokens'] if not t['comment'] and t['text']=='final')
  code=node['text'][first['offset']-node['start']:]
  result.append((name,code[len('final '):code.rindex(name)].strip()))
 assert len(result)==21
 return result

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
    value=paths[0]+'.'+value
  elif owner==STATE and moved(row) and name in ['context','mounted','setState']:
   value='_deps.'+name+('()' if name!='setState' else '')
  elif owner==STAGE and step>=2 and target and target['original_name'].startswith(STAGE+'.'):
   value=target['new_name']
   if target['destination_class']!=dest:
    value=('stageState.' if dest=='StremioTvTunerStageContent' else '_content.')+value
  if value!=name:edits[occ['offset']]=(len(name),value)
 for t in node['tokens']:
  if t['comment']:continue
  name=t['text']
  if name in TYPES:
   target=by_old.get(name)
   if step >= (int(target['step']) if target else 2):edits[t['offset']]=(len(name),TYPES[name])
 old=row['original_name'].split('.')[-1]
 if old!=row['new_name'] and moved(row):
  token=next(t for t in node['tokens'] if not t['comment'] and t['text']==old)
  edits[token['offset']]=(len(old),row['new_name'])
 text=node['text']
 for offset,(length,value) in sorted(edits.items(),reverse=True):
  i=offset-node['start'];text=text[:i]+value+text[i+length:]
 return text

def layout(original,rows,config,parsed,leaves,step):
 by_name={r['original_name']:r for r in rows}
 imports=original[:parsed['declarations'][0]['start']]
 # Package imports prevent relative-URI changes from obscuring probe meaning.
 imports=re.sub(r"import '([^']+)'",lambda m:m.group() if m[1].startswith(('dart:','package:')) else "import 'package:debrify/"+str((Path(SOURCE).parent/m[1])).replace('\\','/')+"'",imports)
 # Resolve package-relative ../ segments without accessing other worktrees.
 import posixpath
 imports=re.sub(r"package:debrify/([^']+)",lambda m:'package:debrify/'+posixpath.normpath(m[1]).removeprefix('lib/'),imports).replace('package:debrify/screens/stremio_tv/stremio_tv_service.dart','package:debrify/services/stremio_tv_service.dart')
 destinations=defaultdict(list);facade=[];scaffold_data,composition,getters,section_scaffolds=scaffolding(view_properties(parsed))
 last=parsed['declarations'][0]['start']
 for d in parsed['declarations']:
  leading=original[last:d['start']];last=d['end']
  if d['name'] not in [STATE,STAGE]:
   row=by_name[d['name']]
   text=leading+moved_body(d,row,rows,config,step)
   if int(row['step'])<=step and row['destination_file']!=SOURCE:destinations[row['destination_file']].append(text)
   else:facade.append(text)
   continue
  if d['name']==STATE and step<3:
   row={'original_name':STATE,'new_name':STATE,'destination_file':SOURCE,'destination_class':STATE}
   facade.append(leading+moved_body(d,row,rows,config,step));continue
  if d['name']==STAGE and step<2:
   row={'original_name':STAGE,'new_name':STAGE,'destination_file':SOURCE,'destination_class':STAGE}
   facade.append(leading+moved_body(d,row,rows,config,step));continue
  groups=defaultdict(list);prior=original.index('{',d['offset'])+1
  for m in d['members']:
   row=by_name[d['name']+'.'+m['name']]
   text=original[prior:m['start']]+moved_body(m,row,rows,config,step);prior=m['end']
   groups[(row['destination_file'],row['destination_class'])].append(text)
  for (path,cls),bodies in groups.items():
   header='class '+cls+' {';extra=''
   if cls==STATE:
    header='class '+STATE+' extends State<StremioTvTuner> implements StremioTvTunerWidgetView {'
    extra=composition
   elif cls=='StremioTvTunerStageState':
    header='class '+cls+' extends State<StremioTvTunerStage> with TickerProviderStateMixin {'
    extra='StremioTvTunerStageContent? _contentCache;\nStremioTvTunerStageContent get _content => _contentCache ??= StremioTvTunerStageContent(this);\n'
   elif cls=='StremioTvTunerStageContent':
    extra='final StremioTvTunerStageState stageState;\nStremioTvTunerStageContent(this.stageState);\nBuildContext get context => stageState.context;\nStremioTvTunerStage get widget => stageState.widget;\n'
   elif cls=='StremioTvTunerOwners':pass
   else:extra=section_scaffolds[next(g for g in GROUPS if cls=='StremioTvTuner'+g.title())]
   forward=leaves[STATE+'._focusRealIndex']
   prefix=forward['text'][:forward['bodyOffset']-forward['start']]
   tail=(getters+'\n'+prefix+'=> _sections.dial.focusRealIndex(realIndex);\n') if cls==STATE else ''
   text=leading+header+'\n'+extra+'\n'.join(bodies)+tail+'\n}\n';leading=''
   if path==SOURCE:facade.append(text)
   else:destinations[path].append(text)
 if step>=3:
  for path,text in scaffold_data.items():destinations[path].append(text)
 all_files=[SOURCE,*destinations]
 def file_imports(path):
  return imports+''.join("import 'package:debrify/"+p[len('lib/'):] +"';\n" for p in all_files if p!=path and p!=SOURCE)
 sources={SOURCE:file_imports(SOURCE)+'\n'.join(facade)+'\n'}
 sources.update({p:file_imports(p)+'\n'.join(b) for p,b in destinations.items()})
 return sources
