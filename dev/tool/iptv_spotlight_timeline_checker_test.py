#!/usr/bin/env python3
"""The complete real checker/reader schedule and opt-in negative fixtures."""
import argparse,copy
from pathlib import Path
from check_verbatim_moves import ROOT,parse,ensure_parser_package
from check_settings_moves import all_nodes,check,configured,tokens
from iptv_spotlight_timeline_checker_fixtures import inputs,layout,SOURCE,STATE,PREFIX,BRIDGE,FORWARDERS
from iptv_spotlight_timeline_source_reader import validate
from occurrence_field_bindings import failures as occurrence_failures
from torbox_callback_identity import check_callback_identities

def self_test(package):
 original,rows,config,parsed,leaves=inputs(package)
 def failures(sources,cfg):return check(original,sources,rows,SOURCE,package,context_guard=True,config=cfg)
 def accept(label,sources,cfg):
  result=validate(original,sources,rows,cfg,package);assert result['source']==original
  print(label+': checker and source reader PASS',flush=True)
 def reject(label,sources,cfg,expected=None):
  try:validate(original,sources,rows,cfg,package)
  except ValueError as error:
   if expected:assert expected in str(error),(label,str(error))
  else:raise AssertionError('checker/reader accepted '+label)
  print(label+': checker and source reader rejected',flush=True)
 layouts={}
 for step in range(4):
  cfg={**config,'completed_step':step};sources=layout(original,rows,cfg,parsed,leaves,step)
  accept('real complete schedule S='+str(step),sources,cfg);layouts[step]=sources
  lookup=all_nodes(parse(sources,package))
  if step:
   for path in sorted({r['destination_file'] for r in rows if 0<int(r['step'])<=step}|{p for p,s in config['scaffold_file_steps'].items() if s<=step}):
    changed=dict(sources);changed.pop(path)
    reject('S='+str(step)+' missing activated '+path,changed,cfg,'Activated destination')
   row=next(r for r in rows if int(r['step'])==1)
   changed=dict(sources);changed[SOURCE]+='\n'+leaves[row['original_name']]['text']+'\n';reject('S='+str(step)+' restored moved leaf',changed,cfg)
  # Retained controller and lifecycle may never leave the facade.
  for owner,name in [('', 'IptvSpotlightTimelineController'),(STATE,'dispose'),(STATE,'_holdOk')]:
   node=lookup[(SOURCE,owner,name)];changed=dict(sources);changed[SOURCE]=changed[SOURCE][:node['start']]+changed[SOURCE][node['end']:]
   reject('S='+str(step)+' retained '+name+' moved out',changed,cfg,'Retained row')
  if step>=2:
   for name in FORWARDERS:
    node=lookup[(SOURCE,STATE,name)]
    for label,body in [('missing',''),('altered',node['text'].replace('_sections.', '_wrongSections.').replace('_owners.','_wrongOwners.'))]:
     changed=dict(sources);changed[SOURCE]=changed[SOURCE][:node['start']]+body+changed[SOURCE][node['end']:]
     reject('S='+str(step)+' '+label+' '+name+' forwarder',changed,cfg)
 cfg={**config,'completed_step':2};sources=layouts[2];lookup=all_nodes(parse(sources,package,occurrence_bindings=True))
 def locate(identity):
  row=next(r for r in rows if r['original_name']==identity)
  key=(row['destination_file'],row['destination_class'],row['new_name']);return key,lookup[key]
 def mutate(identity,label,before,after):
  key,node=locate(identity);assert before in node['text'],(identity,before)
  body=node['text'].replace(before,after,1);assert body!=node['text']
  changed=dict(sources);changed[key[0]]=changed[key[0]][:node['start']]+body+changed[key[0]][node['end']:];reject(label,changed,cfg)
 cases=[
 ('initState','_sections.loading.onViewportMoved','otherLoading.onViewportMoved','listener add receiver swapped'),
 ('dispose','_sections.loading.onViewportMoved','otherLoading.onViewportMoved','listener remove receiver swapped'),
 ('initState','_sections.loading.onViewportMoved','() => _sections.loading.onViewportMoved()','listener add wrapped'),
 ('dispose','_sections.loading.onViewportMoved','() => _sections.loading.onViewportMoved()','listener remove wrapped'),
 ('dispose','_owners.viewportSettle?.cancel();','', 'dispose cancel dropped'),
 ('dispose','_owners.viewportSettle?.cancel();\n\n    _owners.clockTick?.cancel();','_owners.clockTick?.cancel();\n\n    _owners.viewportSettle?.cancel();','dispose reordered'),
 ('initState','seconds: 30','seconds: 1','clock duration'),
 ('_guideRefreshInterval','minutes: 30','minutes: 0','refresh duration'),
 ('_armPointerSelection','milliseconds: 375','milliseconds: 0','dwell duration'),
 ('_accepts','!_deps.mounted() ||','', 'accepts mounted dropped'),
 ('_armPointerSelection','!_deps.mounted() ||','', 'dwell mounted dropped'),
 ('_armPointerSelection','_owners.pointerSettle = null','_owners.viewportSettle = null','block pointer owner swapped'),
 ('_rowHeight','MediaQuery.textScalerOf(_deps.context())','MediaQuery.textScalerOf(savedContext)','cached State context'),
 ('_rowHeight','// Share the adjusted extent','// Cache the adjusted extent','reworded moved comment'),
 ('_loadSchedule','_owners.pendingLoads.remove','pendingLoads.remove','bare owner field'),
 ('_rulerMarks','windowStart: _owners.windowStart','windowStart: windowStart','bare windowStart read with original label'),
 ('_loadSchedule','_owners.pendingLoads.remove','cachedPending.remove','captured owner field'),
 ('_moveVertical','_sections.loading.programmesForRow','_sections.selection.programmesForRow','wrong section receiver'),
 ('_buildRuler','SpotlightTimelinePalette.identityBackground','SpotlightTimelinePalette.timelineBackground','palette receiver swapped'),
 ('_onKeyEvent','_deps.holdOk().handle(event)','_holdOk.handle(event)','bare retained hold'),
 ('_onKeyEvent','_deps.holdOk().handle(event)','_owners.holdOk.handle(event)','replacement hold ownership'),
 ('_onKeyEvent','return _deps.holdOk().handle(event);','final hold = _deps.holdOk(); return hold.handle(event);','cached hold local'),
 ('_onKeyEvent','return _deps.holdOk().handle(event);','final hold = _deps.holdOk; return hold().handle(event);','wrapped hold getter'),
 ('_onKeyEvent','_deps.holdOk().handle(event)','(_deps.holdOk)().handle(event)','parenthesized hold getter'),
 ('_onKeyEvent','_deps.holdOk().handle(event)','later(_deps.holdOk).handle(event)','delayed hold getter'),
 ('_onKeyEvent','_deps.holdOk().handle(event)','deps.holdOk().handle(event)','wrong hold dependency receiver'),
 ('_onKeyEvent','_deps.holdOk().handle(event)','TvHoldOk(onTap: () {}, onHold: () {}).handle(event)','second hold'),
 ('_holdOk','late final TvHoldOk','final TvHoldOk','eager hold field'),
 ('build','physics: const ClampingScrollPhysics()','physics: ClampingScrollPhysics()','removed const'),
 ('_buildRuler','return SizedBox(','return const SizedBox(','new const'),
 ]
 # Leading ordinary comments belong to the original gaps, not the AST member range.
 # Their exact text is covered by the complete file missing-comment proof below.
 for name,before,after,label in cases:
  if label=='dispose reordered':
   before='_owners.viewportSettle?.cancel();\n    _owners.clockTick?.cancel();';after='_owners.clockTick?.cancel();\n    _owners.viewportSettle?.cancel();'
  if label=='reworded moved comment':continue
  mutate(STATE+'.'+name,label,before,after)
 for path,before,after,label in [
  (SOURCE,'_sectionsCache ??=','', 'sections constructed per call'),
  (SOURCE,'holdOk: () => _holdOk','holdOk: () => TvHoldOk(onTap: () {}, onHold: () {})','replacement hold constructed in composition'),
  (SOURCE,'get onExitUp => widget.onExitUp','get onExitUp => () => widget.onExitUp?.call()','wrapped host callback view'),
  (SOURCE,'get channels => widget.channels','get channels => savedChannels','cached channel view'),
  (SOURCE,'view: this','view: savedWidget','stored widget snapshot'),
  (BRIDGE+'spotlight_timeline_cursor.dart','_deps.view','savedWidget','stored section widget'),
  (BRIDGE+'spotlight_timeline_guide_loading.dart','// Share the adjusted extent','// Cache the adjusted extent','reworded moved comment'),
  (SOURCE,'implements SpotlightTimelineWidgetView','implements SpotlightTimelineWidgetView, OtherView','extra interface'),
  (SOURCE,'extends State<SpotlightLiveTimeline> implements','extends WrongState implements','wrong superclass'),
  (SOURCE,'extends State<SpotlightLiveTimeline> implements','extends State<SpotlightLiveTimeline> with ExtraMixin implements','extra mixin'),
 ]:
  assert before in sources[path],(path,before)
  changed=dict(sources);changed[path]=changed[path].replace(before,after,1);reject(label,changed,cfg)
 # Exact re-export surfaces are checked even when method bodies are untouched.
 entry=', '.join(['SpotlightScheduleLoader','SpotlightChannelActivate','SpotlightProgrammeActivate','SpotlightTimelineEntryKey','SpotlightTimelineEntry','SpotlightTimelineSelection'])
 for before,after,label in [(entry,entry+', SpotlightTimelineTrack','extra export name'),(entry,entry.rsplit(', ',1)[0],'missing export name'),(' show '+entry,'','unrestricted export')]:
  changed=dict(sources);changed[SOURCE]=changed[SOURCE].replace(before,after,1);reject(label,changed,cfg,'export')
 # The binder alone aligns the retained-field call as one ORIGINAL field read.
 with configured(cfg):assert not occurrence_failures(leaves,lookup,rows,SOURCE,cfg,package=package)
 for member in ['_rulerMarks','_buildProgrammeTrack']:
  _,node=locate(STATE+'.'+member);values=tokens(node)
  assert any(values[i:i+2]==['windowStart',':'] for i in range(len(values)-1))
  assert not any(o['name']=='windowStart' and o['kind']=='lexical' for o in node.get('occurrences',[]))
 print('original windowStart labels stay labels under the independent binder: PASS',flush=True)
 key,node=locate(STATE+'._rulerMarks');changed=dict(sources)
 changed[key[0]]=changed[key[0]][:node['start']]+node['text'].replace('windowStart: _owners.windowStart','windowStart: windowStart',1)+changed[key[0]][node['end']:]
 mutated=all_nodes(parse(changed,package,occurrence_bindings=True))
 with configured(cfg):errors=occurrence_failures(leaves,mutated,rows,SOURCE,cfg,members={STATE+'._rulerMarks'},package=package)
 assert errors,'binder accepted bare windowStart read'
 print('occurrence alone bare windowStart with original label: rejected',flush=True)
 identity=STATE+'._onKeyEvent';key,node=locate(identity)
 for label,before,after in [
  ('bare field','_deps.holdOk().handle(event)','_holdOk.handle(event)'),
  ('this field','_deps.holdOk().handle(event)','this._holdOk.handle(event)'),
  ('cached local','return _deps.holdOk().handle(event);','final hold = _deps.holdOk(); return hold.handle(event);'),
  ('wrapped getter','return _deps.holdOk().handle(event);','final hold = _deps.holdOk; return hold().handle(event);'),
  ('delayed getter','_deps.holdOk().handle(event)','later(_deps.holdOk).handle(event)'),
  ('replacement owner','_deps.holdOk().handle(event)','_owners.holdOk.handle(event)'),
  ('parenthesized getter','_deps.holdOk().handle(event)','(_deps.holdOk)().handle(event)'),
  ('second hold','_deps.holdOk().handle(event)','TvHoldOk(onTap: () {}, onHold: () {}).handle(event)'),
  ('wrong receiver','_deps.holdOk().handle(event)','deps.holdOk().handle(event)'),
 ]:
  changed=dict(sources);changed[key[0]]=changed[key[0]][:node['start']]+node['text'].replace(before,after,1)+changed[key[0]][node['end']:]
  mutated=all_nodes(parse(changed,package,occurrence_bindings=True))
  with configured(cfg):errors=occurrence_failures(leaves,mutated,rows,SOURCE,cfg,members={identity},package=package)
  assert errors,('binder accepted '+label)
  print('occurrence alone retained hold '+label+': rejected',flush=True)
 # Ownership/construction negatives must also fail the binder alone.
 for label,before,after in [
  ('eager retained field','late final TvHoldOk','final TvHoldOk'),
  ('replacement construction','holdOk: () => _holdOk','holdOk: () => TvHoldOk(onTap: () {}, onHold: () {})'),
 ]:
  changed=dict(sources);changed[SOURCE]=changed[SOURCE].replace(before,after,1)
  mutated=all_nodes(parse(changed,package,occurrence_bindings=True))
  with configured(cfg):errors=occurrence_failures(leaves,mutated,rows,SOURCE,cfg,package=package)
  assert errors,('binder accepted '+label)
  print('occurrence alone retained hold '+label+': rejected',flush=True)
 # A retained final declaration alone cannot mask initialization assignments
 # or a second cached field in a section: prove both through checker + binder.
 for label in ['hold assigned in initState','hold cached in section field']:
  changed=dict(sources)
  if label=='hold assigned in initState':
   key,node=locate(STATE+'.initState')
   changed[key[0]]=changed[key[0]][:node['start']]+node['text'].replace('super.initState();','super.initState(); _holdOk = TvHoldOk(onTap: () {}, onHold: () {});',1)+changed[key[0]][node['end']:]
  else:
   path=BRIDGE+'spotlight_timeline_cursor.dart'
   changed[path]=changed[path].replace('final SpotlightTimelineDependencies _deps;', 'final SpotlightTimelineDependencies _deps; late final TvHoldOk _cachedHold = _deps.holdOk();',1).replace('return _deps.holdOk().handle(event);','return _cachedHold.handle(event);',1)
  reject(label,changed,cfg)
  mutated=all_nodes(parse(changed,package,occurrence_bindings=True))
  with configured(cfg):errors=occurrence_failures(leaves,mutated,rows,SOURCE,cfg,package=package)
  assert errors,('binder accepted '+label)
  print('occurrence alone '+label+': rejected',flush=True)
 with configured(cfg):assert not check_callback_identities(lookup,rows,SOURCE,cfg)
 for spec in cfg['callback_identities']:
  site=spec['sites'][0];key,node=locate(site['member']);values=tokens(node)
  from torbox_callback_identity import arguments,callback_argument
  expr=callback_argument(arguments(values,site['call'])[site.get('occurrence',0)],site)
  index=next(i for i in range(len(values)) if values[i:i+len(expr)]==expr)
  for label,replacement in [('swap',['anotherInstance','.',expr[-1]]),('wrap',['(',')','=>',*expr,'(',')'])]:
   mutated=copy.deepcopy(lookup);edited=list(values);edited[index:index+len(expr)]=replacement
   mutated[key]['tokens']=[{'text':t,'offset':i,'comment':False} for i,t in enumerate(edited)];mutated[key]['formatCommas']=[]
   with configured(cfg):errors=check_callback_identities(mutated,rows,SOURCE,cfg)
   assert errors,(spec['name'],label)
   print('callback alone '+spec['name']+' '+label+': rejected',flush=True)
 live={SOURCE:(ROOT/SOURCE).read_text(),**{p.relative_to(ROOT).as_posix():p.read_text() for p in (ROOT/config['feature']).rglob('*.dart')}}
 accept('live sources',live,config)
 print('All timeline real-config fixtures PASS',flush=True)

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--parser-package',type=Path,required=True);p.add_argument('--broken-fixture',action='store_true');args=p.parse_args()
 if args.broken_fixture:raise AssertionError('deliberately broken checker fixture positive control')
 package=args.parser_package.resolve();ensure_parser_package(package.parent.parent,package)
 self_test(package)
if __name__=='__main__':main()
