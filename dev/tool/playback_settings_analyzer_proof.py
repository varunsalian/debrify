#!/usr/bin/env python3
"""Compare relocated diagnostics with original symbols, never by summed counts."""
import argparse
from collections import Counter
import csv
import json
import re
import subprocess
from pathlib import Path
from check_verbatim_moves import parse
from check_settings_moves import ROOT, all_nodes
from suite_evidence import diagnostics, evidence_dir


def main():
    args=argparse.ArgumentParser()
    args.add_argument('analyzer_output',type=Path)
    args.add_argument('--parser-package',type=Path,required=True)
    args.add_argument('--output',type=Path,required=True)
    options=args.parse_args()
    config=json.loads((ROOT/'dev/tool/playback_settings_checker_config.json').read_text())
    rows=list(csv.DictReader((ROOT/'dev/tool/playback_settings_manifest.tsv').open(),delimiter='\t'))
    source=config['source']
    e=evidence_dir()/'playback_settings'
    baseline=diagnostics(e/'base-analyzer.txt')
    strict=diagnostics(e/'original-strict-analyzer.txt')
    strict=Counter({(sev,source,rule,msg):count for (sev,path,rule,msg),count in strict.items()})
    combined=baseline | strict
    (e/'original-max-analyzer.txt').write_text('\n'.join(' • '.join([sev,msg,path+':1:1',rule]) for (sev,path,rule,msg),count in combined.items() for _ in range(count))+'\n')
    sources={source:(ROOT/source).read_text()}
    sources.update({p.relative_to(ROOT).as_posix():p.read_text() for p in (ROOT/config['feature']).rglob('*.dart')})
    lookup=all_nodes(parse(sources,options.parser_package))
    by_dest={(row['destination_file'],row['destination_class'],row['new_name']):row['original_name'] for row in rows}
    by_dest.update({(source,*row['original_name'].rpartition('.')[::2]):row['original_name'] for row in rows if '.' in row['original_name']})
    partitions=json.loads((ROOT/config['sidecars']['partitions']).read_text())['partitions']
    for key,spec in partitions.items():
        for piece in spec['slices']:
            by_dest[(piece['file'],piece['owner'],piece['name'])]=key
    before=Counter((x['symbol'],x['severity'],x['rule'],x['message']) for x in json.loads((e/'original-strict-symbols.json').read_text()))
    current=Counter()
    scaffold=[]
    for line in options.analyzer_output.read_text().splitlines():
        parts=[x.strip() for x in line.split(' • ')]
        if len(parts)!=4:continue
        sev,msg,loc,rule=parts
        match=re.fullmatch(r'(.*):(\d+):(\d+)',loc)
        if not match:continue
        path,line_no,column=match[1],int(match[2]),int(match[3])
        if path not in sources:continue
        raw=sources[path];lines=raw.splitlines(keepends=True);offset=sum(map(len,lines[:line_no-1]))+column-1
        enclosing=[(key,node) for key,node in lookup.items() if key[0]==path and node['start']<=offset<node['end']]
        if enclosing:
            key,node=min(enclosing,key=lambda pair:pair[1]['end']-pair[1]['start'])
            symbol=by_dest.get(key)
        else:symbol='<imports>'
        if symbol is None:
            scaffold.append({'file':path,'line':line_no,'rule':rule,'message':msg})
        else:current[(symbol,sev,rule,msg)]+=1
    added=current-before
    result={'original_strict':sum(before.values()),'current':sum(current.values()),'additions':[{'identity':key,'count':n} for key,n in added.items()],'scaffold_diagnostics':scaffold,'max_combined_count':sum(combined.values())}
    options.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
    return 1 if added or scaffold else 0


if __name__=='__main__':
    raise SystemExit(main())
