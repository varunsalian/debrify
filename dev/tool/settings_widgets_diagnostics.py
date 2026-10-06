#!/usr/bin/env python3
"""Strict diagnostics by severity/rule/top-level owner/message, never by path."""
import argparse
from collections import Counter
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
from check_verbatim_moves import parse
from settings_widgets_probe import SOURCE, FEATURE, split_sources

ROOT=Path(__file__).resolve().parents[2]

def identity(d):
    return (d['severity'],d['rule'],d['owner'],d['message'])

def additions(base,actual):
    return Counter(map(identity,actual))-Counter(map(identity,base))

def maximum(*runs):
    result=Counter()
    for run in runs: result |= Counter(map(identity,run))
    return [dict(zip(('severity','rule','owner','message'),key)) for key,n in sorted(result.items()) for _ in range(n)]

def fixture_test():
    old={'severity':'INFO','rule':'prefer_const_constructors','owner':'SettingsTile','message':'Use const','file':'original.dart'}
    assert not additions([old],[dict(old,file='moved.dart')])
    assert additions([old],[old,dict(old)])
    assert additions([old],[dict(old,owner='SettingsInfoTile')])
    assert additions([old],[dict(old,rule='unused_import')])
    assert len(maximum([old],[old]))==1
    print('Diagnostics fixtures: relocation PASS; added/re-owned/new-rule rejected; maximum never sum PASS')

def analyze(root,paths,package,label,evidence):
    proc=subprocess.run(['dart','analyze','--format','machine',*paths],cwd=root,capture_output=True,text=True)
    (evidence/(label+'.txt')).write_text(proc.stdout+proc.stderr)
    sources={p:(root/p).read_text() for p in paths}
    parsed=parse(sources,package)
    records=[]
    for line in proc.stdout.splitlines():
        parts=line.split('|',7)
        if len(parts)!=8: continue
        severity,_,rule,file,line_number,column,_,message=parts
        relative=Path(file).relative_to(root).as_posix()
        text=sources[relative]
        offset=sum(len(s)+1 for s in text.splitlines()[:int(line_number)-1])+int(column)-1
        nodes=parsed[relative]['declarations']
        owner=next((n['name'] for n in nodes if n['start']<=offset<n['end']),'<directives>')
        records.append(dict(severity=severity,rule=rule.lower(),owner=owner,message=message,file=relative,line=int(line_number)))
    return records

def capture(rev,package,evidence,split=False):
    scratch=ROOT/'.dart_tool/settings_widgets/diagnostics';scratch.mkdir(parents=True,exist_ok=True)
    directory=Path(tempfile.mkdtemp(dir=scratch)).resolve();directory.rmdir()
    subprocess.run(['git','worktree','add','--detach',str(directory),rev],cwd=ROOT,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        subprocess.run(['flutter','pub','get'],cwd=directory,check=True,stdout=subprocess.DEVNULL)
        source=(directory/SOURCE).read_text()
        # Strict policy in the original directory preserves relative URIs.
        options=directory/Path(SOURCE).parent/'analysis_options.yaml'
        options.write_text('include: ../../../features/analysis_options.yaml\n')
        paths=[SOURCE]+[p.relative_to(directory).as_posix() for p in (directory/FEATURE).glob('*.dart')]
        original=analyze(directory,paths,package,'original-strict',evidence)
        import re
        qualified=re.sub(r"(?m)^import '([^']+)';",lambda m:"import 'package:debrify/"+(Path(SOURCE).parent/m[1]).resolve().relative_to(ROOT/'lib').as_posix()+"';" if not m[1].startswith('package:') else m[0],source)
        # Resolve paths lexically against ROOT; no external files are accessed.
        (directory/SOURCE).write_text(qualified)
        qualifying=analyze(directory,paths,package,'qualified-strict',evidence)
        extra=additions(original,qualifying)
        assert all(k[1]=='directives_ordering' for k in extra),extra
        induced=[dict(zip(('severity','rule','owner','message'),k)) for k,n in extra.items() for _ in range(n)]
        split_records=[]
        if split:
            parsed=parse({'original':source},package)['original']
            files=split_sources(source,parsed)
            for file,text in files.items():
                dest=directory/file;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(text)
            subprocess.run(['dart','format',*[str(directory/p) for p in files]],check=True,stdout=subprocess.DEVNULL)
            split_records=analyze(directory,list(files),package,'split-strict',evidence)
            assert not additions(qualifying,split_records), additions(qualifying,split_records)
        return {'revision':rev,'original':original,'qualified':qualifying,'qualification_induced':induced,'split':split_records,'maximum':maximum(original,qualifying,split_records)}
    finally:
        subprocess.run(['git','worktree','remove','--force',str(directory)],cwd=ROOT,check=True,stdout=subprocess.DEVNULL)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('command',choices=['record','compare','fixtures'])
    p.add_argument('--rev');p.add_argument('--parser-package',type=Path)
    p.add_argument('--output',type=Path);p.add_argument('--baseline',type=Path);p.add_argument('--split',action='store_true')
    args=p.parse_args()
    if args.command=='fixtures': fixture_test();return
    assert args.rev and args.parser_package and args.output
    args.output.parent.mkdir(parents=True,exist_ok=True)
    result=capture(args.rev,args.parser_package.resolve(),args.output.parent,args.split)
    if args.command=='compare':
        base=json.loads(args.baseline.read_text())
        observed=result['maximum']
        added=additions(base['maximum'],observed)
        result['added']=[list(k)+[n] for k,n in added.items()]
        args.output.write_text(json.dumps(result,indent=2)+'\n')
        assert not added,added
    else: args.output.write_text(json.dumps(result,indent=2)+'\n')
    print('Strict per-owner diagnostics: PASS;',len(result['maximum']),'maximum identities;',len(result['qualification_induced']),'qualification-induced ordering identities')
if __name__=='__main__': main()
