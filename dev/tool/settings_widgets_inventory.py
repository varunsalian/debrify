#!/usr/bin/env python3
"""Reproduce the original declaration/importer report with an isolated analyzer."""
import argparse,json,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'dev/tool'))
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--rev',required=True)
p.add_argument('--parser-package',type=Path,required=True)
p.add_argument('--report',type=Path,required=True)
p.add_argument('--evidence',type=Path,required=True)
args=p.parse_args()
from check_verbatim_moves import parse
from settings_widgets_probe import GROUPS,EXTERNAL,SOURCE,FEATURE
package=args.parser_package.resolve()
original=subprocess.check_output(['git','show',args.rev+':'+SOURCE],cwd=ROOT,text=True);ast=parse({'original':original},package)['original']
public={n['name'] for n in ast['declarations'] if not n['name'].startswith('_')};assert len(public)==47
owner={n:g for g,names in GROUPS.items() for n in names}
paths=[line.split(':',1)[1] for line in subprocess.check_output(['git','grep','-l','settings_widgets.dart',args.rev,'--','lib','test'],cwd=ROOT,text=True).splitlines() if line.endswith('.dart')]
kernel=package.parent/'settings_widgets_inventory.dill'
subprocess.run(['dart','compile','kernel','--packages='+str(package),'-o',str(kernel),str(ROOT/'dev/tool/settings_widgets_inventory.dart.txt')],check=True,stdout=subprocess.DEVNULL)
units=json.loads(subprocess.check_output(['dart',str(kernel)],input=json.dumps({p:subprocess.check_output(['git','show',args.rev+':'+p],cwd=ROOT,text=True) for p in paths}),text=True))
importers=[]
for path,unit in units.items():
 directives=[]
 for directive in unit['directives']:
  m=re.match(r"import '([^']+)'",directive)
  if not m:continue
  uri=m[1]
  target='lib/'+uri[len('package:debrify/'):] if uri.startswith('package:debrify/') else (ROOT/Path(path).parent/uri).resolve().relative_to(ROOT).as_posix() if not uri.startswith('package:') and not uri.startswith('dart:') else None
  if target==SOURCE: directives.append(directive)
 if not directives:continue
 identifiers=set(unit['identifiers'])
 names=sorted(identifiers & public)
 # Unused imports remain part of the inventory; do not fix them.
 importers.append(dict(path=path,directives=directives,names=names,runnable=path.startswith('test/') and path.endswith('_test.dart')))
assert len(importers)==132,len(importers)
assert sum(i['path'].startswith('lib/') for i in importers)==117
assert sum(i['runnable'] for i in importers)==14
ci=set(l.strip() for l in subprocess.check_output(['git','show',args.rev+':dev/tool/ci_behavior_tests.txt'],cwd=ROOT,text=True).splitlines() if l.strip() and not l.startswith('#'))
missing=[i['path'] for i in importers if i['runnable'] and i['path'] not in ci]
assert len(missing)==6,missing
out=args.evidence
out.mkdir(parents=True,exist_ok=True)
(out/'importer_inventory.json').write_text(json.dumps(dict(importers=importers,missing_ci=missing),indent=2)+'\n')
lines=['# Settings widgets dependency and wiring report','',f'Original formatted reference R `{args.rev}`. Generated from analyzer declarations, scanner tokens and parsed import directives; relative and package URIs resolved lexically within this checkout. No production caller is edited in Step 0.','',f'60 declarations, 47 public names, 13 private declarations/variables; 132 importing files (117 lib, 15 test, 14 runnable). No prefix or hide directive. Public names remain reachable through the planned facade; the source reader and surface test pin every name.','', '## Declaration ownership and cross-file references','', '| Declaration | Destination | Cross-file public references | State reads | Comment fragments |','| --- | --- | --- | --- | --- |']
graph={g:set() for g in GROUPS};comments=[]
for n in ast['declarations']:
 name=n['name'];g=owner[name];identifiers={t['text'] for t in n['tokens'] if not t['comment']};cross=sorted(v for v in identifiers & set(owner) if owner[v]!=g)
 assert all(not v.startswith('_') for v in cross),(name,cross)
 graph[g].update(owner[v] for v in cross)
 reads=sorted(set(re.findall(r'\bwidget\.([A-Za-z_]\w*)',n['text'])))
 state='widget: '+', '.join(reads) if reads else '—'
 for word in ['context','mounted']:
  if word in identifiers:state+='; '+word
 fragments=[t['text'] for t in n['tokens'] if t['comment']]
 comments.append(dict(declaration=name,destination=FEATURE+'settings_'+g+'.dart',fragments=fragments))
 lines.append('| `'+name+'` | `settings_'+g+'.dart` | '+(', '.join('`'+v+'`' for v in cross) or '—')+' | '+state+' | '+str(len(fragments))+'; retained with this leaf |')
(out/'comment_inventory.json').write_text(json.dumps(comments,indent=2)+'\n')
lines+=['','Every doc and interior comment stays with its exact analyzer leaf. The comment inventory below is complete, including ordinary prose and private-name doc links; these links are never renamed. Whitespace-only gaps contain no unowned comment fragment.','']
for n in comments:
 if n['fragments']:
  lines+=['### `'+n['declaration']+'` comments','', '```dart', '\n'.join(n['fragments']), '```','']
lines+=['## Service and platform imports','','| File | Narrow import | Exit milestone |','| --- | --- | --- |','| settings_connection_card.dart | services/main_page_bridge.dart show MainPageBridge | composition-injected sidebar focus callback |','| settings_legacy_mode_dialog.dart | services/profiles/profile_bootstrap.dart show ProfileBootstrap | composition-injected legacy reason |','| settings_links.dart | package:url_launcher/url_launcher.dart | composition-wired launcher port |','','No other service/native operation is introduced. Original imports retain their unshown form in Step 0. Destinations use only the exact shows after creation.','', '## Public-reference import DAG','','```mermaid','graph TD']
for g,targets in graph.items():
 for t in sorted(targets):lines.append(f'  {g} --> {t}')
lines+=['```','']
def visit(g,stack):
 assert g not in stack,(g,stack)
 for other in graph[g]:visit(other,stack+[g])
for g in graph:visit(g,[])
lines+=['The graph is acyclic. No cross-file private reference exists, so type_aliases is empty. Sorted imports are generated by `settings_widgets_probe.py`; the split probe analyzes exactly these files under feature strict options.','', '## Importing callers','','| Importer | Used facade names | Import directive |','| --- | --- | --- |']
for i in importers:lines.append('| `'+i['path']+'` | '+(', '.join('`'+n+'`' for n in i['names']) or 'none (original unused import)')+' | `'+i['directives'][0]+'` |')
lines+=['','## CI additions','','Missing runnable direct importers:','']+['- `'+p+'`' for p in missing]+['','Also register the helper consumers `test/theme/goldens_test.dart` and `test/theme/contrast_audit_test.dart` when absent, and all nine new tests. Never register `test/theme/surface_gallery.dart`.','', '## Wiring checklist','','Step 0: every declaration remains in R. Each destination is still pending. For every later move: copy the whole leaf and comments, wire the public references/imports above, re-export its public name, run the manifest, reader, diagnostics and affected tests, then remove its original declaration.','']
lines += ['- [ ] `'+n['name']+'` → `settings_'+owner[n['name']]+'.dart` (production remains original at Step 0)' for n in ast['declarations']]
args.report.write_text('\n'.join(lines)+'\n')
print('Deps: 60 leaves, 47 public, 132 importing files / 14 runnable; missing CI:',missing)
