#!/usr/bin/env python3
"""Prove ORIGINAL editor source expectations through checker and reader.

The four existing hidden-controls assertions are retained unchanged. Two
additional source-only mutations are masked by core services behaviorally;
this command explicitly records their structural rejection instead.
"""
import argparse
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--original-root', type=Path, required=True)
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--only', action='append')
    args = parser.parse_args()
    from check_verbatim_moves import ROOT, parse
    from check_settings_moves import check
    from edit_profile_source_reader import validate
    from edit_profile_checker_fixtures import inputs
    if '.dart_tool/edit_profile_parser/' not in str(args.parser_package):
        parser.error('use the isolated edit_profile parser')
    original, rows, config, _ = inputs(args.parser_package)
    source = config['source']
    target = args.original_root/source
    assert target.read_text() == original
    evidence = Path(subprocess.check_output(
        ['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'],
        cwd=ROOT, text=True).strip())/'refactor-evidence/edit_profile'
    output = evidence/'original-mutations.json'
    d = json.loads(output.read_text())
    command = ['flutter', 'test', '--no-pub', '--concurrency=1', '--reporter=json',
               'test/profiles/profile_source_guard_test.dart', '--plain-name',
               'profile editor keeps feature controls hidden behind one switch']
    with (evidence/'source-proof-original.jsonl').open('w') as out, (evidence/'source-proof-original.stderr').open('w') as err:
        result = subprocess.run(command, cwd=args.original_root, stdout=out, stderr=err)
    assert result.returncode == 0
    members = next(n for n in parse({'original':original},args.parser_package)['original']['declarations']
                   if n['name']=='_EditProfileScreenState')['members']
    build = next(n for n in members if n['name']=='build')
    first = original.index('if (EditProfileScreen.showFeaturePolicyControls) ...[')
    tokens = build['tokens']
    opening = next(i for i,t in enumerate(tokens) if t['offset']>=first and t['text']=='[')
    depth = 0
    for t in tokens[opening:]:
        if t['text']=='[': depth+=1
        elif t['text']==']': depth-=1
        if depth==0:
            end=t['offset']+len(t['text'])
            if original[end:end+1]==',':end+=1
            break
    block=original[first:end]
    mutants=[
        ('hidden-controls-removed', original[:first]+original[end:], 'S existing expectation'),
        ('hidden-controls-duplicated', original[:end]+'\n'+block+original[end:], 'S existing expectation'),
        ('ceiling-seed', original.replace('ProfilePolicy.defaultsFor(_role).enabled','ProfilePolicy.allAllowedFor(_role).enabled',1), 'S existing expectation'),
        ('changed-create-default', original.replace('return ProfilePolicy.defaultsFor(role);','return ProfilePolicy(enabled: selected);',1), 'S existing expectation'),
        ('clamp-omission-core-masked', original.replace('if (ceilingLens.allows(_role, feature)) feature,','feature,',1), 'S registry decoding masks the behavioral omission in the Kid scenario'),
        ('picker-finally-copy-release', original.replace('await CacheScratchCleanup.releasePickerCopy(pickerCopy);','',1), 'S picker copy cleanup has no recording seam; exact finally statement pinned'),
        ('lazy-authorization-declaration', original.replace('late ProfileAuthorizationContext _authorization = widget.authorization;', 'ProfileAuthorizationContext _authorization = widget.authorization;',1), 'S lazy declaration; no behavioral timing or evaluation-count claim'),
        ('active-rollback-core-masked', original.replace('persisted?.lifecycle != UserProfileLifecycle.active','persisted?.lifecycle == UserProfileLifecycle.active',1), 'S core rollback authorization masks attempted deletion of an active row'),
    ]
    records=[]
    for name, mutant, classification in mutants:
        if args.only and name not in args.only:continue
        errors=check(original,{source:mutant},rows,source,args.parser_package,context_guard=True,config=config)
        assert errors, name
        try:validate(original,{source:mutant},rows,config,args.parser_package)
        except ValueError as error:reader=str(error)
        else:raise AssertionError('Reader accepted '+name)
        try:
            target.write_text(mutant)
            with (evidence/(name+'.jsonl')).open('w') as out,(evidence/(name+'.stderr')).open('w') as err:
                result=subprocess.run(command,cwd=args.original_root,stdout=out,stderr=err)
            events=[json.loads(l) for l in (evidence/(name+'.jsonl')).read_text().splitlines() if l.startswith('{')]
            assertions=[x['error'] for x in events if x['type']=='error' and x.get('isFailure') and 'Expected:' in x.get('error','')]
            assert result.returncode!=0 and assertions,(name,result.returncode)
            records.append(dict(name=name,classification=classification,command=command,cwd=str(args.original_root),exit=result.returncode,checker_errors=errors,reader_error=reader,assertions=assertions,proved=True))
            print(name+' checker + reader + retained Flutter expectation: PASS',flush=True)
        finally:target.write_text(original)
    names={r['name'] for r in records}
    d['source_only']=[r for r in d.get('source_only',[]) if r['name'] not in names]+records
    output.write_text(json.dumps(d,indent=2)+'\n')
    return 0


if __name__=='__main__':
    raise SystemExit(main())
