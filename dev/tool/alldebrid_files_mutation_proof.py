#!/usr/bin/env python3
"""Run the frozen Step-0 mutants ONLY in an explicitly supplied scratch clone.

The source is restored in finally. JSON evidence and patches are kept outside
tracked files. Compiler, runner and timeout errors never constitute a kill.
"""
import argparse
import difflib
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = 'lib/screens/alldebrid/alldebrid_files_screen.dart'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scratch', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--case', action='append', default=[])
    args = parser.parse_args()
    scratch = args.scratch.resolve()
    assert (scratch / '.git').is_dir(), 'A normal scratch git clone is required'
    assert scratch != Path('/Users/varunbsalian/Documents/Projects/debrify-wt/alldebrid-files'), 'Never mutate the destination worktree'
    path = scratch / SOURCE
    original = path.read_text()
    base = subprocess.run(['git','show','49c53e2e:'+SOURCE],cwd=scratch,capture_output=True,text=True,check=True).stdout
    assert original.startswith(base), 'Original implementation plus appended read-only seam required'
    cases = json.loads((ROOT/'dev/tool/alldebrid_files_mutation_cases.json').read_text())
    selected = [c for c in cases if not args.case or c['name'] in args.case]
    assert selected
    evidence = args.evidence.resolve(); evidence.mkdir(parents=True, exist_ok=True)
    results = []
    try:
        for case in selected:
            changed = original
            for edit in case['edits']:
                # Read the real original owning method, bounded at the next
                # State declaration (never match another method's same text).
                marker = re.search(r'^  (?:@override\n  )?(?!//)\S[^\n]*\b'+re.escape(edit['member'])+r'\s*(?:\(|\{|=>|=)', changed, re.M)
                assert marker, edit['member']
                if '(' in marker.group() or '{' in marker.group():
                    end_match = re.search(r'^  }\s*$', changed[marker.end():], re.M)
                    assert end_match, edit['member']
                    end = marker.end()+end_match.end()
                else:
                    end = changed.index(';',marker.end())+1
                body = changed[marker.start():end]
                assert edit['before'] in body, edit
                body = body.replace(edit['before'],edit['after'],1)
                changed = changed[:marker.start()]+body+changed[end:]
            assert changed != original
            path.write_text(changed)
            stem = case['kind']+'-'+case['name']
            (evidence/(stem+'.patch')).write_text(''.join(difflib.unified_diff(original.splitlines(True),changed.splitlines(True),fromfile=SOURCE,tofile=SOURCE)))
            paths = sorted({t.split('::',1)[0] for t in case['tests']})
            names = [t.split('::',1)[1] for t in case['tests']]
            regex = '^(?:'+'|'.join(map(re.escape,names))+')$'
            command = ['flutter','test','--no-pub','--concurrency=1','--reporter=json',*paths,'--name',regex]
            with (evidence/(stem+'.jsonl')).open('w') as out, (evidence/(stem+'.stderr')).open('w') as err:
                result = subprocess.run(command,cwd=scratch,stdout=out,stderr=err)
            events = [json.loads(l) for l in (evidence/(stem+'.jsonl')).read_text().splitlines() if l.startswith('{')]
            tests={};suites={};outcomes={};failures={};messages={};done=False
            for event in events:
                kind=event.get('type')
                if kind=='suite':suites[event['suite']['id']]=event['suite']['path'].replace(str(scratch)+'/', '')
                elif kind=='testStart':tests[event['test']['id']]=event['test']
                elif kind in ('error','print'):
                    ident=event.get('testID');messages.setdefault(ident,[]).append(event.get('error',event.get('message','')))
                    if kind=='error':failures.setdefault(ident,[]).append(event)
                elif kind=='testDone' and not event.get('hidden'):
                    t=tests[event['testID']];identity=suites[t['suiteID']]+'::'+t['name'];outcomes[identity]=event['result']
                elif kind=='done':done=True
            killed=[];survivors=[];invalid=[];assertions={}
            for identity in case['tests']:
                ident=next((i for i,t in tests.items() if suites[t['suiteID']]+'::'+t['name']==identity),None)
                text='\n'.join(messages.get(ident,[]))
                # Widgets report captured TestFailure as a print followed by an
                # error; ordinary tests report isFailure directly. Both must
                # show an assertion, not a compiler/runner failure or timeout.
                assertion=any(e.get('isFailure') for e in failures.get(ident,[])) or ('Expected:' in text and 'Actual:' in text)
                infrastructure=any(not error.get('isFailure') and error.get('error','').startswith(('Compilation failed', 'Failed to load \"', 'Test timed out after', 'TimeoutException')) for error in failures.get(ident,[]))
                if done and outcomes.get(identity) in ('failure','error') and assertion and not infrastructure:
                    killed.append(identity);assertions[identity]=text[:16000]
                elif outcomes.get(identity)=='success':survivors.append(identity)
                else:invalid.append(identity)
            row={**case,'command':command,'exit':result.returncode,'done':done,'original_sha256':hashlib.sha256(original.encode()).hexdigest(),'mutant_sha256':hashlib.sha256(changed.encode()).hexdigest(),'outcomes':outcomes,'killed':killed,'survivors':survivors,'invalid':invalid,'assertion_evidence':assertions}
            (evidence/(stem+'.result.json')).write_text(json.dumps(row,indent=2,ensure_ascii=False)+'\n')
            results.append({k:v for k,v in row.items() if k!='assertion_evidence'})
            path.write_text(original)
            (evidence/'results.json').write_text(json.dumps(results,indent=2)+'\n')
            print(stem, 'killed',len(killed),'survivors',len(survivors),'invalid',len(invalid),flush=True)
    finally:
        path.write_text(original)
    return 1 if any(r['survivors'] or r['invalid'] for r in results) else 0

if __name__ == '__main__':
    raise SystemExit(main())
