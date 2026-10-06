#!/usr/bin/env python3
"""Frozen real-config schedules, original/moved negatives and binder proofs."""
import argparse,json
from pathlib import Path
from check_verbatim_moves import ROOT,parse,ensure_parser_package
from check_settings_moves import all_nodes,check,configured,tokens
from iptv_settings_two_pane_checker_fixtures import inputs,layout,SOURCE,STATE,PREFIX,BRIDGE
from iptv_settings_two_pane_source_reader import validate
from torbox_callback_identity import arguments,argument_ranges,callback_argument,check_callback_identities
from occurrence_field_bindings import failures as binding_failures

def self_test(package):
 original,rows,config,parsed,leaves=inputs(package)
 def failures(src,cfg):return check(original,src,rows,SOURCE,package,context_guard=True,config=cfg)
 def accept(label,src,cfg):
  errors=failures(src,cfg);assert not errors,(label,errors)
  assert validate(original,src,rows,cfg,package)['source']==original
  print(label+': checker and reader PASS')
 def reject(label,src,cfg,expected=None):
  errors=failures(src,cfg);assert errors,('accepted '+label)
  if expected:assert any(expected in e for e in errors),(label,errors)
  try:validate(original,src,rows,cfg,package)
  except ValueError:pass
  else:raise AssertionError('reader accepted '+label)
  print(label+': checker and reader rejected')
 by={r['original_name']:r for r in rows}
 def key_for(identity,step):
  owner,_,name=identity.rpartition('.');r=by.get(identity)
  if r:return (r['destination_file'],r['destination_class'],r['new_name']) if int(r['step'])<=step else (SOURCE,owner,name or identity)
  r=by[owner]
  return (r['destination_file'],r['new_name'],name) if int(r['step'])<=step else (SOURCE,owner,name)
 layouts={}
 for step in range(4):
  cfg={**config,'completed_step':step};src=layout(original,rows,cfg,parsed,leaves,step);layouts[step]=src
  accept('real schedule S='+str(step),src,cfg)
  if step:
   for path in sorted({r['destination_file'] for r in rows if int(r['step'])<=step}|{p for p,s in config['scaffold_file_steps'].items() if s<=step}):
    changed=dict(src);changed.pop(path);reject('S='+str(step)+' deleted activated '+path,changed,cfg,'Activated destination')
   r=next(r for r in rows if int(r['step'])==1)
   changed=dict(src);changed[SOURCE]+='\n'+leaves[r['original_name']]['text']+'\n';reject('S='+str(step)+' restored moved leaf',changed,cfg)
  if step>=2:
   for before,after,label in [
    ('IptvAutoRefreshDialog, ','','missing export'),
    ('IptvAutoRefreshDialog, ','SixthName, IptvAutoRefreshDialog, ','extra export'),
    ('iptv_auto_refresh_dialog.dart','iptv_two_pane_row.dart','wrong export source'),
    ('show IptvSettingsTwoPane, IptvSettingsTwoPaneState;','show IptvSettingsTwoPane, IptvSettingsTwoPaneState;\nvoid extra() {}','facade declaration'),
   ]:
    changed=dict(src);assert before in changed[SOURCE];changed[SOURCE]=changed[SOURCE].replace(before,after,1);reject('S='+str(step)+' '+label,changed,cfg)
  # Neither inherited access nor future files are silently required at S=0/1.
  lookup=all_nodes(parse(src,package,occurrence_bindings=True))
  def mutate(identity,label,before,after):
   key=key_for(identity,step);node=lookup[key];assert before in node['text'],(step,identity,before)
   changed=dict(src);changed[key[0]]=changed[key[0]][:node['start']]+node['text'].replace(before,after,1)+changed[key[0]][node['end']:]
   reject('S='+str(step)+' '+label,changed,cfg)
  field=lambda n:('_owners.'+n[1:]) if step>=2 else n
  call=lambda n:('_sections.navigation.'+by[STATE+'.'+n]['new_name']) if step>=2 else n
  for identity,before,after,label in [
   (STATE+'.dispose',field('_railScroll')+'.dispose();','', 'dispose step dropped'),
   (STATE+'.dispose',field('_railScroll')+'.dispose();\n    '+field('_dest')+'.dispose();',field('_dest')+'.dispose();\n    '+field('_railScroll')+'.dispose();','dispose reordered'),
   (STATE+'.focusAddPane','if (mounted) '+call('_enterPane')+'();',call('_enterPane')+'();','mounted guard dropped'),
   (STATE+'._syncStats',"(p.password ?? '').hashCode,",'','password signature dropped'),
   (STATE+'._syncStats','...widget.refreshingIds,','','refreshing signature dropped'),
   (STATE+'._syncRailNodes','while ('+field('_railNodes')+'.length < _railCount)', 'while ('+field('_railNodes')+'.length != _railCount)','grow-only changed'),
   (STATE+'._focusRail','index >= _railCount || ','','rendered rail bound removed'),
   (STATE+'._buildRail','return SizedBox(','return const SizedBox(','const added'),
   (STATE+'._buildPane','const '+('IptvTwoPanePaneHeader' if step>=1 else '_PaneHeader')+'(',('IptvTwoPanePaneHeader' if step>=1 else '_PaneHeader')+'(','const removed'),
   (STATE+'._syncStats','// Rebuilt from an explicit field list','// Changed explicit field list','comment reworded'),
  ]:mutate(identity,label,before,after)
  # Immediate postframe callback has the same work but violates timing.
  key=key_for(STATE+'.focusAddPane',step);node=lookup[key]
  before='WidgetsBinding.instance.addPostFrameCallback((_) {';assert before in node['text']
  changed=dict(src);body=node['text'].replace(before,'(() {',1).replace('    });','    })();',1)
  changed[key[0]]=changed[key[0]][:node['start']]+body+changed[key[0]][node['end']:];reject('S='+str(step)+' postframe immediate',changed,cfg)
  # Every assignment and conditional branch is independently checked before
  # normalization, not merely accepted by a permissive receiver erasure.
  sidecar=json.loads((ROOT/config['sidecars']['callbacks']).read_text())
  from iptv_settings_two_pane_contracts import callback_errors
  for ordinal,spec in enumerate(sidecar['sites']):
   if spec['named_argument']!='onFocused' and '?' not in spec['expression']:continue
   key=key_for(spec['member'],step);node=lookup[key]
   expr=spec['expression'] if step==0 else spec['step1_expression'] if step==1 else spec['destination_expression']
   calls=arguments([v for v in tokens(node) if not v.startswith(('//','/*'))],config['callback_call_aliases'].get(spec['call'],spec['call']) if step>=1 else spec['call'])
   actual=callback_argument(calls[spec['occurrence']],spec);assert actual==expr
   # Token-offset replacements avoid changing another equal callback site.
   vals=[t for t in node['tokens'] if not t['comment'] and t['offset'] not in node.get('formatCommas',[])]
   sequence=[t['text'] for t in vals]
   selected=argument_ranges(sequence,config['callback_call_aliases'].get(spec['call'],spec['call']) if step>=1 else spec['call'])[spec['occurrence']]
   left,right=next((a,b) for a,b in selected if sequence[a:a+2]==[spec['named_argument'],':'])
   start=left+2
   assert sequence[start:right]==expr
   # Mutate each branch receiver separately for conditionals, and each
   # destination receiver/type for onFocused assignments.
   indexes=[i for i,v in enumerate(expr) if v in ['_focusRail','focusRailAt','_dest','dest'] or v.endswith('Dest')]
   if not indexes:indexes=[0]
   for branch,i in enumerate(indexes):
    edited=sequence[:start+i]+['WrongReceiver']+sequence[start+i+1:]
    changed={**lookup,key:dict(node)}
    changed[key]['tokens']=[{'text':v,'offset':i,'comment':False} for i,v in enumerate(edited)];changed[key]['formatCommas']=[]
    errors=callback_errors(changed,cfg,rows)
    assert any('callback expression changed: '+str(ordinal)+' ' in e for e in errors),(ordinal,branch,errors)
  print('S='+str(step)+' exact assignments and conditional branches rejected')
  mutate(STATE+'._buildRail','assignment closure hoisted',
         'onFocused: () => '+field('_dest')+'.value = '+call('_destForRail')+'(i)',
         'onFocused: cachedOnFocused')
  for identity,before,after in [
   ('_RailEntryState.build','widget.onFocused','otherWidget.onFocused'),
   ('_PaneRowState.build','widget.onLeft','otherWidget.onLeft'),
   ('_MethodCardState.build','widget.onRight','otherWidget.onRight'),
  ]:mutate(identity,'piece block callback receiver swapped',before,after)
  with configured(cfg):assert not check_callback_identities(lookup,rows,SOURCE,cfg)
  for spec in config['callback_identities']:
   site=spec['sites'][0];key=key_for(site['member'],step);node=lookup[key];values=[v for v in tokens(node) if not v.startswith(('//','/*'))]
   call=config['callback_call_aliases'].get(site['call'],site['call']) if step>=1 else site['call']
   expr=callback_argument(arguments(values,call)[site['occurrence']],site)
   selected=argument_ranges(values,call)[site['occurrence']]
   left,right=next((a,b) for a,b in selected if values[a:a+2]==[site['named_argument'],':'])
   start=left+2
   assert values[start:right]==expr
   for replacement in [['otherReceiver','.',expr[-1]],['(',')','=>',*expr,'(',')']]:
    edited=values[:start]+replacement+values[start+len(expr):];changed={**lookup,key:dict(node)}
    changed[key]['tokens']=[{'text':v,'offset':i,'comment':False} for i,v in enumerate(edited)];changed[key]['formatCommas']=[]
    with configured(cfg):assert check_callback_identities(changed,rows,SOURCE,cfg),(step,spec['name'])
  print('S='+str(step)+' callback utility alone receiver swaps and wraps rejected')
  if step>=2:
   for path,before,after,label in [
    (BRIDGE+'iptv_settings_two_pane_widget.dart','_sectionsCache ??=','', 'sections constructed per call'),
    (BRIDGE+'iptv_settings_two_pane_widget.dart','final _owners = IptvSettingsTwoPaneOwners();','IptvSettingsTwoPaneOwners get _owners => IptvSettingsTwoPaneOwners();','owners lazy/per call'),
    (BRIDGE+'iptv_settings_two_pane_widget.dart','final _owners = IptvSettingsTwoPaneOwners();','late final _owners = IptvSettingsTwoPaneOwners();','owners lazy field'),
    (BRIDGE+'iptv_settings_two_pane_rail.dart','_deps.widget()','cachedWidget','stored widget snapshot'),
    (BRIDGE+'iptv_settings_two_pane_rail.dart','_deps.widget()','otherWidget()','wrong live getter'),
    (BRIDGE+'iptv_settings_two_pane_rail.dart','_deps.context()','context','State context lexical'),
    (BRIDGE+'iptv_settings_two_pane_rail.dart','_deps.widget()','this.widget','inherited this in section'),
    (BRIDGE+'iptv_settings_two_pane_rail.dart','valueListenable: _owners.dest','valueListenable: dest','owner field bare'),
    (BRIDGE+'iptv_settings_two_pane_preference_panes.dart','styleIcon(kIptvStyleChoices','_sections.navigation.styleIcon(kIptvStyleChoices','block local function rebound'),
    (BRIDGE+'iptv_settings_two_pane_preference_panes.dart','paneNode(row++)','paneNode(_owners.row++)','lexical row rebound'),
   ]:
    if before==after:continue
    changed=dict(src);assert before in changed[path],(path,before);changed[path]=changed[path].replace(before,after,1);reject('S='+str(step)+' '+label,changed,cfg)
   mutate(STATE+'.build','lexical build context captured','AppThemeScope.of(context)','AppThemeScope.of(_deps.context())')
   for before,after,label in [('extends State<IptvSettingsTwoPane>','extends WrongState','superclass'),('extends State<IptvSettingsTwoPane>','extends State<IptvSettingsTwoPane> implements Extra','interface'),('extends State<IptvSettingsTwoPane>','extends State<IptvSettingsTwoPane> with Extra','mixin')]:
    path=BRIDGE+'iptv_settings_two_pane_widget.dart';changed=dict(src);changed[path]=changed[path].replace(before,after,1);reject('S='+str(step)+' State '+label,changed,cfg,'Widget class header')
   path=BRIDGE+'iptv_settings_two_pane_rail.dart';changed=dict(src);changed[path]="import 'package:debrify/screens/settings/iptv_settings_two_pane.dart';\n"+changed[path];reject('S='+str(step)+' facade back import',changed,cfg)
 cfg={**config,'completed_step':2};lookup=all_nodes(parse(layouts[2],package,occurrence_bindings=True))
 with configured(cfg):assert not binding_failures(leaves,lookup,rows,SOURCE,cfg,package=package)
 for identity,before,after,label in [
  (STATE+'._buildRail','valueListenable: _owners.dest','valueListenable: dest','record field qualification'),
  (STATE+'._buildPane','switch (dest)','switch (_owners.dest.value)','lexical dest parameter'),
  (STATE+'._buildAppearancePane','styleIcon(kIptvStyleChoices','_sections.navigation.styleIcon(kIptvStyleChoices','block function'),
  (STATE+'._buildPlayerGuidePane','            styleRow(\n','            _sections.navigation.styleRow(\n','player-guide block function'),
 ]:
  src=dict(layouts[2]);key=key_for(identity,2);node=lookup[key];assert before in node['text'];src[key[0]]=src[key[0]][:node['start']]+node['text'].replace(before,after,1)+src[key[0]][node['end']:]
  changed=all_nodes(parse(src,package,occurrence_bindings=True))
  with configured(cfg):errors=binding_failures(leaves,changed,rows,SOURCE,cfg,package=package)
  assert errors,(label,'binder accepted');print('occurrence utility alone '+label+': rejected')
  if label=='record field qualification':qualification_defaults(leaves,lookup,changed,rows,cfg,package)

 live={SOURCE:(ROOT/SOURCE).read_text(),**{p.relative_to(ROOT).as_posix():p.read_text() for p in (ROOT/config['feature']).rglob('*.dart')}}
 accept('live sources',live,config)
 print('All IPTV two-pane real-config fixtures PASS')

def qualification_defaults(leaves,lookup,changed,rows,cfg,package):
 # The integrator may use either default. No shared file is changed.
 import types,re
 module_text=(ROOT/'dev/tool/occurrence_field_bindings.py').read_text()
 marker=re.compile(r"binding_config.get\('mandatory_qualification', (?:False|True)\)")
 assert len(marker.findall(module_text))==1
 for default in [False,True]:
  module=types.ModuleType('iptv_occurrence_default_'+str(default))
  source=marker.sub("binding_config.get('mandatory_qualification', "+str(default)+")",module_text)
  exec(compile(source,str(ROOT/'dev/tool/occurrence_field_bindings.py'),'exec'),module.__dict__)
  with configured(cfg):
   assert not module.failures(leaves,lookup,rows,SOURCE,cfg,package=package)
   errors=module.failures(leaves,changed,rows,SOURCE,cfg,package=package)
  assert any('Bare owner field reference:' in error for error in errors),(default,errors)
  print('explicit qualification rejects bare owner field with shared default '+str(default))

def qualification_probe(package):
 original,rows,cfg,parsed,leaves=inputs(package)
 cfg={**cfg,'completed_step':2};src=layout(original,rows,cfg,parsed,leaves,2)
 lookup=all_nodes(parse(src,package,occurrence_bindings=True))
 path=BRIDGE+'iptv_settings_two_pane_rail.dart'
 assert 'valueListenable: _owners.dest' in src[path]
 src[path]=src[path].replace('valueListenable: _owners.dest','valueListenable: dest',1)
 changed=all_nodes(parse(src,package,occurrence_bindings=True))
 qualification_defaults(leaves,lookup,changed,rows,cfg,package)

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--parser-package',type=Path,required=True);p.add_argument('--broken-fixture',action='store_true');p.add_argument('--qualification-defaults-only',action='store_true');a=p.parse_args()
 if a.broken_fixture:raise AssertionError('deliberately broken checker fixture positive control')
 package=a.parser_package.resolve();ensure_parser_package(package.parent.parent,package);(qualification_probe if a.qualification_defaults_only else self_test)(package)
if __name__=='__main__':main()
