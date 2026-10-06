#!/usr/bin/env python3
"""Every step through the complete checker/reader, plus real-config negatives."""
import argparse,copy,json
from pathlib import Path
from check_verbatim_moves import ROOT,parse,ensure_parser_package
from check_settings_moves import all_nodes,check,configured,tokens
from stremio_tv_tuner_checker_fixtures import inputs,layout,SOURCE,STATE,STAGE,PREFIX,BRIDGE
from stremio_tv_tuner_source_reader import validate
from torbox_callback_identity import arguments,callback_argument,check_callback_identities
from occurrence_field_bindings import failures as _occurrence_failures

def self_test(package):
 original,rows,config,parsed,leaves=inputs(package)
 def failures(sources,cfg):return check(original,sources,rows,SOURCE,package,context_guard=True,config=cfg)
 def occurrence_failures(original_nodes,bindings,bound_rows,source,bound_config,**kwargs):
  with configured(bound_config):
   return _occurrence_failures(original_nodes,bindings,bound_rows,source,bound_config,**kwargs)
 def accept(label,sources,cfg):
  errors=failures(sources,cfg);assert not errors,(label,errors)
  result=validate(original,sources,rows,cfg,package);assert result['source']==original
  print(label+': checker and source reader PASS')
 def reject(label,sources,cfg,expected=None):
  errors=failures(sources,cfg);assert errors,('accepted '+label)
  if expected:assert any(expected in e for e in errors),(label,errors)
  try:validate(original,sources,rows,cfg,package)
  except ValueError:pass
  else:raise AssertionError('reader accepted '+label)
  print(label+': checker and source reader rejected')
 layouts={}
 for step in range(5):
  cfg={**config,'completed_step':step};sources=layout(original,rows,cfg,parsed,leaves,step)
  accept('real complete schedule S='+str(step),sources,cfg);layouts[step]=sources
  if step:
   for path in sorted({r['destination_file'] for r in rows if 0<int(r['step'])<=step}|{p for p,s in config['scaffold_file_steps'].items() if s<=step}):
    changed=dict(sources);changed.pop(path)
    reject('S='+str(step)+' missing activated '+path,changed,cfg,'Activated destination')
  # Retention is a separate contract from default destination/facade fallback.
  retained=next(r for r in rows if r['original_name']==STATE+'.build')
  lookup=all_nodes(parse(sources,package));node=lookup[(SOURCE,STATE,'build')]
  changed=dict(sources);changed[SOURCE]=changed[SOURCE][:node['start']]+changed[SOURCE][node['end']:]
  reject('S='+str(step)+' retained build moved out',changed,cfg,'Retained row')
  if step:
   row=next(r for r in rows if int(r['step'])==1)
   changed=dict(sources);changed[SOURCE]+='\n'+leaves[row['original_name']]['text']+'\n'
   reject('S='+str(step)+' restored moved leaf',changed,cfg)
  if step>=3:
   node=lookup[(SOURCE,STATE,'_focusRealIndex')]
   for label,body in [('missing',''),('altered',node['text'].replace('_sections.dial','_sections.channels'))]:
    changed=dict(sources);changed[SOURCE]=changed[SOURCE][:node['start']]+body+changed[SOURCE][node['end']:]
    reject('S='+str(step)+' '+label+' controller forwarder',changed,cfg)
 cfg={**config,'completed_step':3};sources=layouts[3]
 lookup=all_nodes(parse(sources,package,occurrence_bindings=True))
 def locate(identity):
  row=next((r for r in rows if r['original_name']==identity),None)
  if row:
   key=(row['destination_file'],row['destination_class'],row['new_name'])
  else:
   owner,_,name=identity.rpartition('.');row=next(r for r in rows if r['original_name']==owner)
   key=(row['destination_file'],row['new_name'],name)
  return key,lookup[key]
 def mutate(identity,label,before,after):
  key,node=locate(identity);assert before in node['text'],(identity,before)
  body=node['text'].replace(before,after,1);assert body!=node['text']
  changed=dict(sources);changed[key[0]]=changed[key[0]][:node['start']]+body+changed[key[0]][node['end']:]
  reject(label,changed,cfg)
 for identity,before,after,label in [
  (STATE+'._setActive','milliseconds: 180','milliseconds: 0','settle duration'),
  (STATE+'._setActive','_deps.setState(() {});','otherState.setState(() {});','settle block State receiver swapped'),
  (STATE+'._syncTick','_deps.setState(() {});','otherState.setState(() {});','broadcast tick State receiver swapped'),
  (STATE+'._openChannelList','if (ctx.mounted) setSheet','if (_deps.mounted()) setSheet','sheet tick context receiver swapped'),
  (STATE+'._buildWide','_owners.dialScroll.jumpTo(target)','_owners.pageController.jumpTo(target)','wheel block scroll receiver swapped'),
  (STATE+'._buildWide','_sections.dial.snapDial()','anotherDial.snapDial()','snap block dial receiver swapped'),
  (STATE+'._focusWhenAttached','node.requestFocus()','anotherNode.requestFocus()','postframe focus receiver swapped'),
  (STAGE+'._buildContent','widget.ident','savedIdent','content ident snapshot'),
  (STAGE+'._cascade','_textFx','stageState._textFx','stageState receiver outside content'),
  (STATE+'._setActive','if (!widget.autoRefresh) _deps.setState(() {});','_deps.setState(() {});','settle setState gate'),
  (STATE+'._syncTick','seconds: 15','seconds: 1','tick duration'),
  (STATE+'._syncTick','if (route != null && !route.isCurrent) return;','','route current guard'),
  (STATE+'.initState','_sections.dial.onDialScroll','() => _sections.dial.onDialScroll()','listener add wrapped'),
  (STATE+'.initState','_sections.dial.onDialScroll','otherDial.onDialScroll','listener add swapped'),
  (STATE+'.dispose','_sections.dial.onDialScroll','() => _sections.dial.onDialScroll()','listener remove wrapped'),
  (STATE+'.dispose','_sections.dial.onDialScroll','otherDial.onDialScroll','listener remove swapped'),
  (STATE+'.dispose','_owners.activeId.dispose();\n    _owners.centredId.dispose();','_owners.centredId.dispose();\n    _owners.activeId.dispose();','tuner dispose reorder'),
  (STATE+'.dispose','_owners.settle?.cancel();','','tuner dispose drop'),
  (STAGE+'.dispose','_ken.dispose();\n    _textFx.dispose();','_textFx.dispose();\n    _ken.dispose();','Stage dispose reorder'),
  (STAGE+'.dispose','_ken.dispose();','','Stage dispose drop'),
  ('_DialCardState.dispose','widget.centredId?.removeListener(_onCentredChanged);','','card dispose listener drop'),
  ('_DialCardState.dispose','widget.centredId?.removeListener(_onCentredChanged);\n    super.dispose();','super.dispose();\n    widget.centredId?.removeListener(_onCentredChanged);','card dispose reorder'),
  (STATE+'._openActions','Navigator.of(ctx).pop();','Navigator.of(_deps.context()).pop();','sheet lexical context captured'),
  (STATE+'._buildWide','ScrollConfiguration.of(_deps.context())','ScrollConfiguration.of(context)','State context made lexical'),
  (STATE+'._openChannelList','setSheet(() {});','_deps.setState(() {});','lexical sheet setter rebound'),
  (STATE+'._channelListRow','_sections.channels.setActive(widget.channels[idx])','otherChannels.setActive(widget.channels[idx])','block callback target receiver swapped'),
  (STATE+'._buildWide','_sections.channels.channelById(activeId)','_sections.channels.channelById(_owners.activeId.value)','VLB parameter captured by owner field'),
  (STATE+'._buildWide','valueListenable: _owners.activeId','valueListenable: activeId','bare owner field under VLB'),
  (STAGE+'._buildContent','stageState.cascade(', 'cachedCascade(', 'Stage cascade tear-off captured'),
  (STAGE+'._buildContent','widget.hideNowPlaying','savedHideNowPlaying','content widget snapshot'),
  (STATE+'._dialItemExtent','138.0 + 16.0','138.0','dial static value'),
  ('_Stage','StremioTvTunerStageState()','WrongStageState()','wrong split Stage State type'),
  (STATE+'._tick','every second','every minute','reworded comment'),
  (STATE+'._buildWide','final stage = StremioTvTunerStage(','final stage = const StremioTvTunerStage(','new const'),
  ('_Stage','const StremioTvTunerStage(','StremioTvTunerStage(','removed const'),
 ]:mutate(identity,label,before,after)
 # Exact scaffold negatives apply outside moved-body comparison too.
 for path,before,after,label in [
  (SOURCE,'_sectionsCache ??=','', 'sections constructed per call'),
  (PREFIX+'stremio_tv_tuner_stage.dart','_contentCache ??=','', 'content owner constructed per call'),
  (PREFIX+'stremio_tv_tuner_stage.dart','StremioTvTunerStageContent? _contentCache;','late StremioTvTunerStageContent _contentCache;','late content cache'),
  (PREFIX+'stremio_tv_tuner_stage_content.dart','stageState.context','savedContext','cached Stage context'),
  (PREFIX+'stremio_tv_tuner_stage_content.dart','stageState.widget','savedWidget','cached Stage widget'),
  (BRIDGE+'stremio_tv_tuner_layout.dart','_deps.view','otherView','wrong live widget getter'),
  (BRIDGE+'stremio_tv_tuner_channels.dart','_deps.view','savedWidget','stored widget snapshot'),
  (PREFIX+'stremio_tv_tuner_stage_content.dart','stageState.widget','() => stageState.widget','wrapped content getter'),
  (SOURCE,'get onFocusHeader => widget.onFocusHeader','get onFocusHeader => () => widget.onFocusHeader()','wrapped host callback view'),
 ]:
  assert before in sources[path],(path,before)
  changed=dict(sources);changed[path]=changed[path].replace(before,after,1);reject(label,changed,cfg)
 for before,after,label in [
  ('extends State<StremioTvTuner> implements','extends WrongState implements','changed superclass'),
  ('implements StremioTvTunerWidgetView','implements StremioTvTunerWidgetView, OtherView','extra interface'),
  ('extends State<StremioTvTuner> implements','extends State<StremioTvTuner> with ExtraMixin implements','extra mixin'),
  ('class '+STATE,'final class '+STATE,'class modifier'),
  ('class '+STATE,'base class '+STATE,'base class modifier'),
  ('class '+STATE,'sealed class '+STATE,'sealed class modifier'),
 ]:
  changed=dict(sources);changed[SOURCE]=changed[SOURCE].replace(before,after,1);reject(label,changed,cfg,'Widget class header')
 changed=dict(sources);path=BRIDGE+'stremio_tv_tuner_layout.dart'
 changed[path]="import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_tuner.dart';\n"+changed[path]
 reject('feature imports facade',changed,cfg,'must not import its facade')
 # Header additions cannot be borrowed by a different class.
 changed=dict(sources);path=BRIDGE+'stremio_tv_tuner_dial.dart'
 changed[path]=changed[path].replace('class StremioTvTunerDial {','class StremioTvTunerDial implements StremioTvTunerWidgetView {',1)
 reject('interface addition on another class',changed,cfg)
 # Exercise each opt-in occurrence extension without whole-body normalization.
 assert not occurrence_failures(leaves,lookup,rows,SOURCE,cfg)
 static=next(r for r in rows if r['original_name']==STATE+'._dialItemExtent')
 changed_rows=copy.deepcopy(rows);changed_static=next(r for r in changed_rows if r['original_name']==static['original_name'])
 changed_static.update(destination_file=BRIDGE+'stremio_tv_tuner_owners.dart',destination_class='StremioTvTunerOwners')
 key,node=locate(static['original_name']);changed_sources=dict(sources)
 changed_sources[key[0]]=changed_sources[key[0]][:node['start']]+changed_sources[key[0]][node['end']:]
 owner_path=changed_static['destination_file'];owner_text=changed_sources[owner_path]
 start=owner_text.index('{',owner_text.index('class StremioTvTunerOwners'))+1
 changed_sources[owner_path]=owner_text[:start]+'\n'+node['text']+'\n'+owner_text[start:]
 changed_lookup=all_nodes(parse(changed_sources,package,occurrence_bindings=True))
 changed_cfg=copy.deepcopy(cfg);changed_cfg['record_fields'][STATE].append('_dialItemExtent')
 errors=occurrence_failures(leaves,changed_lookup,changed_rows,SOURCE,changed_cfg)
 assert any('qualification lost' in e or 'Bare owner field reference' in e for e in errors),errors
 print('occurrence alone static moved to record and read bare: rejected')
 default_cfg=copy.deepcopy(changed_cfg);default_cfg.pop('record_owners')
 assert not occurrence_failures(leaves,changed_lookup,changed_rows,SOURCE,default_cfg)
 print('occurrence alone tuner record qualification is opt-in: PASS')
 changed_cfg=copy.deepcopy(cfg);changed_cfg.pop('record_fields')
 assert occurrence_failures(leaves,lookup,rows,SOURCE,changed_cfg)
 print('occurrence alone unrestricted record fields include dial statics: rejected')
 changed_cfg={**cfg,'occurrence_type_renames':False}
 errors=occurrence_failures(leaves,lookup,rows,SOURCE,changed_cfg,members={'_Stage'})
 assert any('name/scope changed' in e for e in errors),errors
 print('occurrence alone split State rename requires opt-in: rejected')
 key,node=locate('_Stage');changed=dict(sources)
 changed[key[0]]=changed[key[0]][:node['start']]+node['text'].replace('StremioTvTunerStageState()','WrongStageState()')+changed[key[0]][node['end']:]
 errors=occurrence_failures(leaves,all_nodes(parse(changed,package,occurrence_bindings=True)),rows,SOURCE,cfg,members={'_Stage'})
 assert any('name/scope changed' in e for e in errors),errors
 print('occurrence alone wrong split State type: rejected')
 # Identity utility alone must reject both wrapping and same-class receiver swaps.
 def callback_failures(bindings):
  with configured(cfg):
   return check_callback_identities(bindings,rows,SOURCE,cfg)
 assert not callback_failures(lookup)
 for spec in cfg['callback_identities']:
  for site in spec['sites']:
   key,node=locate(site['member']);values=tokens(node)
   call=cfg.get('callback_call_aliases',{}).get(site['call'],site['call'])
   calls=arguments(values,call);expression=callback_argument(calls[site.get('occurrence',0)],site)
   indexes=[i for i in range(len(values)) if values[i:i+len(expression)]==expression]
   assert indexes
   for label,replacement in [('swap',['anotherInstance','.',expression[-1]]),('wrap',['(',')','=>',*expression,'(',')'])]:
    mutated=copy.deepcopy(lookup);edited=list(values);start=indexes[0];edited[start:start+len(expression)]=replacement
    mutated[key]['tokens']=[{'text':t,'offset':i,'comment':False} for i,t in enumerate(edited)];mutated[key]['formatCommas']=[]
    assert callback_failures(mutated),(spec['name'],label)
    print('callback alone '+spec['name']+' '+label+': rejected')
 # Live source, even when the feature is absent at step 0, always gets checked.
 live={SOURCE:(ROOT/SOURCE).read_text(),**{p.relative_to(ROOT).as_posix():p.read_text() for p in (ROOT/config['feature']).rglob('*.dart')}}
 accept('live sources',live,config)
 print('All tuner real-config fixtures PASS')

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--parser-package',type=Path,required=True);parser.add_argument('--broken-fixture',action='store_true');args=parser.parse_args()
 if args.broken_fixture:raise AssertionError('deliberately broken checker fixture positive control')
 package=args.parser_package.resolve();ensure_parser_package(package.parent.parent,package)
 self_test(package)
if __name__=='__main__':main()
