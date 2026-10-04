#!/usr/bin/env python3
"""Pin relocated diagnostics to the frozen ORIGINAL per-symbol maxima."""
import argparse,csv,json,re,sys
from collections import Counter
from pathlib import Path
root=Path(__file__).resolve().parents[2];sys.path.insert(0,str(root/'dev/tool'))
from check_verbatim_moves import parse
from check_settings_moves import all_nodes
parser=argparse.ArgumentParser();parser.add_argument('analyzer');parser.add_argument('--probe',type=Path);parser.add_argument('--parser-package',type=Path,required=True);a=parser.parse_args()
app=a.probe or root;source='lib/widgets/home/spotlight_board.dart';feature='lib/features/spotlight_board'
config=json.loads((app/'dev/tool/spotlight_board_checker_config.json').read_text())
sources={source:(app/source).read_text()};sources.update({str(p.relative_to(app)):p.read_text() for p in (app/feature).rglob('*.dart')})
nodes=all_nodes(parse(sources,a.parser_package))
rows=list(csv.DictReader((root/'dev/tool/spotlight_board_manifest.tsv').open(),delimiter='\t'))
origins={(r['destination_file'],r['destination_class'],r['new_name']):r['original_name'] for r in rows}
classes={r['new_name']:r['original_name'] for r in rows if not r['destination_class'] and '.' not in r['original_name']}
reverse={v:k for k,v in config['type_renames'].items()};observed=Counter();failed=[]
for line in Path(a.analyzer).read_text().splitlines():
 m=re.match(r'^\s*(error|warning|info) • (.*) • (\S+?):(\d+):(\d+) • (\S+)\s*$',line)
 if not m:continue
 severity,message,file,ln,col,rule=m.groups()
 if file not in sources:continue
 text=sources[file];offset=sum(map(len,text.splitlines(keepends=True)[:int(ln)-1]))+int(col)-1
 candidates=[(k,n) for k,n in nodes.items() if k[0]==file and n['start']<=offset<n['end']]
 if rule=='directives_ordering':symbol='@imports'
 elif candidates:
  key,node=min(candidates,key=lambda x:x[1]['end']-x[1]['start']);symbol=origins.get(key)
  if symbol is None:
   owner=classes.get(key[1],reverse.get(key[1],key[1]));name=classes.get(key[2],reverse.get(key[2],key[2]))
   if name==owner and owner in {r['original_name'] for r in rows if not r['destination_class']}:symbol=owner
   elif key[1] in classes:symbol=owner+'.'+name
   elif file==source:symbol=owner+'.'+name if owner else name
   else:symbol=None
 else:symbol=None
 if symbol is None:failed.append('Unregistered diagnostic: '+line)
 else:observed[(severity,rule,symbol,message)]+=1
inventory=json.loads((root/'dev/tool/spotlight_board_analyzer_inventory.json').read_text())
allowed=Counter({(r['severity'],r['rule'],r['symbol'],r['message']):r['maximum'] for r in inventory['entries']})
for identity,count in (observed-allowed).items():failed.append(str((identity,count)))
print('Observed diagnostics:',sum(observed.values()));print('\n'.join(failed));assert not failed
print('Strict rule/symbol/message maxima: zero additions')
