#!/usr/bin/env python3
"""ORIGINAL mutations, B and S separately; assertion kills only, no load errors.

Own scratch checkout only. Restores ORIGINAL bytes even if a proof fails.
Timeouts are discarded and rerun serially; they are never mutation evidence.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from check_verbatim_moves import ROOT, parse
from stremio_tv_catalogs_evidence import EVIDENCE, run
from stremio_tv_catalogs_probe import SOURCE
from suite_evidence import outcomes


def assertions(path):
    tests={};failed=set();invalid=[]
    for line in path.read_text().splitlines():
        try:e=json.loads(line)
        except ValueError:continue
        if e.get('type')=='testStart':tests[e['test']['id']]=e['test']['name']
        if e.get('type') in ('error','print'):
            message=e.get('error',e.get('message',''))
            if 'Expected:' in message:failed.add(tests.get(e['testID'],''))
            if e.get('type')=='error' and ('TimeoutException after' in message or 'timed out after' in message.lower() or message.startswith('Failed to load') or 'Compilation failed' in message):invalid.append(message)
    return failed,invalid


def main():
    p=argparse.ArgumentParser();p.add_argument('--parser-package',type=Path,required=True);p.add_argument('--kind',choices=['B','S'],required=True);p.add_argument('--original-worktree',type=Path,required=True);p.add_argument('--positive',default='stremio_tv_catalogs/characterization');p.add_argument('--only');p.add_argument('--cases',type=Path,default=ROOT/'dev/tool/stremio_tv_catalogs_original_mutations.json');p.add_argument('--label',default='original');a=p.parse_args()
    assert a.label in ('original','review-0b')
    assert a.cases.resolve().is_relative_to(ROOT/'dev/tool')
    scratch=a.original_worktree.resolve();assert scratch==ROOT/'.dart_tool/stremio_tv_catalogs_original'
    package=a.parser_package.resolve();assert package.is_relative_to(ROOT/'.dart_tool')
    revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=scratch,text=True).strip()
    pristine=(scratch/SOURCE).read_text();expected=subprocess.check_output(['git','show','0cb50df7:'+SOURCE],cwd=ROOT,text=True);assert pristine==expected
    positive_path=EVIDENCE/(a.positive+'.jsonl');positive=outcomes(positive_path)[0]
    positive_env=json.loads(positive_path.with_suffix('.env.json').read_text());assert not positive_env['tree_changed_during_run'];assert set(positive.values())=={'success'}
    nodes={}
    for d in parse({SOURCE:pristine},package)[SOURCE]['declarations']:
        nodes[d['name']]=d
        for m in d['members']:nodes[d['name']+'.'+m['name']]=m
    cases=json.loads(a.cases.read_text());cases=[c for c in cases if c['kind']==a.kind]
    out=EVIDENCE/f'stremio_tv_catalogs/{a.label}-{a.kind}-mutations.json';results=json.loads(out.read_text())['results'] if a.only and out.exists() else []
    for c in cases:
        if a.only and c['id']!=a.only:continue
        changed=pristine;versions={}
        for edit in c['edits']:
            member=edit.get('member');text=versions.get(member,nodes[member]['text']) if member else changed
            assert text.count(edit['before'])==edit.get('count',1),(c['id'],edit,text.count(edit['before']))
            replacement=text.replace(edit['before'],edit['after'])
            if member:assert changed.count(text)==1;changed=changed.replace(text,replacement,1);versions[member]=replacement
            else:changed=replacement
        name=f'stremio_tv_catalogs/{a.label}-{a.kind}-{c["id"]}'
        try:
            (scratch/SOURCE).write_text(changed)
            for attempt in range(3):
                run(name,[c['test'],'--no-pub','--concurrency=1','--timeout=120s','--plain-name='+c['assertion']],scratch)
                path=EVIDENCE/(name+'.jsonl');actual=outcomes(path)[0];rejected,invalid=assertions(path)
                if not invalid:break
                # A timeout cannot be a kill or baseline classification.
                for suffix in ['.jsonl','.env.json','.stderr']:path.with_suffix(suffix).unlink(missing_ok=True)
                assert all('Timeout' in s or 'timed out' in s for s in invalid),invalid
                print('Discarded contention timeout; rerunning '+c['id'],flush=True)
            assert not invalid,invalid
            failed={k for k,v in actual.items() if v in ('failure','error')}
            allowed={k for k,v in positive.items() if k.split('::')[0]==c['test'] and c['assertion'] in k.split('::',1)[1]}
            assert allowed and failed and failed<=allowed,(c['id'],'compile/load or unexpected failure',failed,allowed)
            assert any(c['assertion'] in name for name in rejected),(c['id'],'no named assertion failure',rejected)
            env=json.loads(path.with_suffix('.env.json').read_text());assert not env['tree_changed_during_run']
            record=dict(id=c['id'],kind=a.kind,assertion=c['assertion'],failed=sorted(failed),assertion_failures=sorted(rejected),revision=revision,tested_tree=env['tested_tree'],production_sha256=hashlib.sha256(changed.encode()).hexdigest(),evidence=str(path))
            results=[r for r in results if r['id']!=c['id']]+[record]
            out.write_text(json.dumps(dict(kind=a.kind,original=revision,positive=a.positive,positive_tree=positive_env['tested_tree'],results=results),indent=2)+'\n')
            print('ASSERTION KILL '+a.kind+' '+c['id'],flush=True)
        finally:(scratch/SOURCE).write_text(pristine)
        assert (scratch/SOURCE).read_text()==expected
    if not a.only:assert len(results)==len(cases)
    print(f'{a.kind}: {len(results)}/{len(cases)} named assertion kills',flush=True)

if __name__=='__main__':main()
