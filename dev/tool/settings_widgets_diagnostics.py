#!/usr/bin/env python3
"""Strict diagnostics by severity/rule/top-level owner/message, never by path."""
import argparse
from collections import Counter
import json
import re
import shutil
import subprocess
import sys
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

def validated_output(machine,summary):
    # Dart 3.12's machine format suppresses its completion summary. Require a
    # separate default-format run, with the same fatal flags and targets.
    # Documented diagnostic statuses are 0/1/2/3; crashes (including 4/70)
    # must never turn into an empty, apparently passing diagnostic set.
    for label,proc in [('machine',machine),('summary',summary)]:
        if proc.returncode not in (0,1,2,3):
            raise ValueError(f'{label} analyzer failed with exit {proc.returncode}')
        if not proc.stdout.strip() or proc.stderr.strip():
            raise ValueError(f'{label} analyzer output is empty or has unexpected stderr')
    rows=[]
    escapes={'\\':'\\','|':'|','n':'\n','r':'\r'}
    for line in machine.stdout.splitlines():
        fields=[''];escaped=False
        for char in line:
            if escaped:
                if char not in escapes:
                    raise ValueError('Invalid machine escape')
                fields[-1]+=escapes[char];escaped=False
            elif char=='\\': escaped=True
            elif char=='|': fields.append('')
            else: fields[-1]+=char
        if escaped or len(fields)!=8:
            raise ValueError('Unparseable machine diagnostic')
        severity,kind,rule,file,line_number,column,length,message=fields
        if (severity not in ('INFO','WARNING','ERROR') or
            not re.fullmatch(r'[A-Z_]+',kind) or not re.fullmatch(r'[A-Z_0-9]+',rule) or
            not Path(file).is_absolute() or not message or
            not all(re.fullmatch(r'\d+',v) for v in (line_number,column,length)) or
            int(line_number)<1 or int(column)<1):
            raise ValueError('Invalid machine diagnostic fields')
        rows.append(fields)
    lines=summary.stdout.strip().splitlines()
    summaries=[line for line in lines if re.fullmatch(r'\d+ issues? found\.|No issues found!',line)]
    if len(summaries)!=1 or lines[-1]!=summaries[0]:
        raise ValueError('Missing or ambiguous analyzer completion summary')
    count=0 if summaries[0]=='No issues found!' else int(summaries[0].split()[0])
    if count!=len(rows):
        raise ValueError(f'Analyzer summary count {count} differs from {len(rows)} machine diagnostics')
    expected=max({'INFO':1,'WARNING':2,'ERROR':3}[row[0]] for row in rows)
    if machine.returncode!=expected or summary.returncode!=expected:
        raise ValueError('Analyzer diagnostic severity/exit status mismatch')
    return rows

def fixture_test():
    old={'severity':'INFO','rule':'prefer_const_constructors','owner':'SettingsTile','message':'Use const','file':'original.dart'}
    assert not additions([old],[dict(old,file='moved.dart')])
    assert additions([old],[old,dict(old)])
    assert additions([old],[dict(old,owner='SettingsInfoTile')])
    assert additions([old],[dict(old,rule='unused_import')])
    assert len(maximum([old],[old]))==1
    def proc(code,out,err=''):return subprocess.CompletedProcess(['dart','analyze'],code,out,err)
    diagnostic='INFO|LINT|PREFER_CONST_CONSTRUCTORS|/fixture.dart|1|1|4|Use const\n'
    summary=proc(1,'Analyzing fixture.dart...\n\n1 issue found.\n')
    assert len(validated_output(proc(1,diagnostic),summary))==1
    for severity,code in [('WARNING',2),('ERROR',3)]:
        assert len(validated_output(proc(code,diagnostic.replace('INFO',severity)),proc(code,summary.stdout)))==1
    # Exercise a real subprocess failure, rather than treating absent records
    # as a successful analyzer run.
    failure=subprocess.run([sys.executable,'-c','raise SystemExit(70)'],capture_output=True,text=True)
    negatives=[('subprocess-exit-70',failure,summary),
               ('crash-exit-4',proc(4,diagnostic),summary),
               ('signal-exit',proc(-9,diagnostic),summary),
               ('empty',proc(0,''),proc(0,'No issues found!\n')),
               ('unparseable',proc(1,'not a diagnostic\n'),summary),
               ('bad-field',proc(1,diagnostic.replace('|1|1|4|','|x|1|4|')),summary),
               ('missing-summary',proc(1,diagnostic),proc(1,'Analyzing fixture.dart...\n')),
               ('count-mismatch',proc(1,diagnostic),proc(1,'2 issues found.\n')),
               ('exit-mismatch',proc(0,diagnostic),summary),
               ('summary-failure',proc(1,diagnostic),failure)]
    for name,machine,completion in negatives:
        try:validated_output(machine,completion)
        except ValueError:pass
        else:raise AssertionError('Accepted '+name)
    print('Diagnostics fixtures: relocation/max PASS; added/re-owned/new-rule rejected; 3 diagnostic statuses PASS; 10 invalid runs rejected (including subprocess exit 70)')

def analyze(root,paths,package,label,evidence):
    evidence.mkdir(parents=True,exist_ok=True)
    cache=root/'.dart_tool/settings_widgets/analyzer-cache';cache.mkdir(parents=True,exist_ok=True)
    command=['dart','analyze','--fatal-infos','--cache',str(cache)]
    proc=subprocess.run([*command,'--format','machine',*paths],cwd=root,capture_output=True,text=True)
    (evidence/(label+'.txt')).write_text(proc.stdout+proc.stderr)
    # Validate failure before launching another analyzer or invoking the parser.
    if proc.returncode not in (0,1,2,3):
        raise ValueError(f'machine analyzer failed with exit {proc.returncode}')
    summary=subprocess.run([*command,*paths],cwd=root,capture_output=True,text=True)
    (evidence/(label+'-summary.txt')).write_text(summary.stdout+summary.stderr)
    rows=validated_output(proc,summary)
    sources={p:(root/p).read_text() for p in paths}
    parsed=parse(sources,package)
    records=[]
    for parts in rows:
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
