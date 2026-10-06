#!/usr/bin/env python3
"""Step 0b ORIGINAL-only site mutations; core-masked sites are explicit S proofs."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

TEST = 'test/features/edit_profile/presentation/legacy_edit_profile/edit_profile_review_closure_test.dart'
REFRESH = 'operationActor = await _refreshSameManagingAdmin(\n              operationActor.profileId,\n            );'
EDIT_REFRESH = 'operationActor = await _refreshSameManagingAdmin(\n          operationActor.profileId,\n        );'
AUTH_REFRESH = '_authorization = await _refreshSameManagingAdmin(\n        operationActor.profileId,\n      );'


def specifications():
    result = []
    def add(name, member, before, after, cases, count=1, site=None):
        record = dict(name='0b-'+name, member=member, before=before, after=after,
                      cases=cases, file=TEST, count=count)
        if site is not None: record['site'] = site
        result.append(record)
    add('save-start-validation', '_save', 'await _validateManagingAdmin(operationActor);', '',
        ['0b Save edit rejects '+x+' actor after loaded options' for x in ['stale','demoted']])
    add('create-post-update-refresh', '_save', REFRESH, '', ['0b create refresh after staged update keeps changed Admin authority'])
    add('edit-post-publish-refresh', '_save', EDIT_REFRESH, '', ['0b own Admin publish refresh precedes later engine validation'])
    add('edit-post-pin-refresh', '_save', 'operationActor = await _refreshSameManagingAdmin(\n            operationActor.profileId,\n          );', '', ['0b own Admin PIN refresh and edit recovery dialog precede pop'])
    for create, target in [(True,'staged.id'), (False,'savedProfileId')]:
        indent = '            ' if create else '        '
        before='await _applyEngineAssignments(\n'+indent+'  '+target+',\n'+indent+'  snapshot.selectedEngines,\n'+indent+'  operationActor,\n'+indent+');'
        add(('create' if create else 'edit')+'-engine-apply', '_save', before, '', ['0b '+('create' if create else 'edit')+' engine seeds and selected assignments reach target only'])
    add('engine-target-active', '_applyEngineAssignments', 'targetProfileId: targetProfileId,', 'targetProfileId: ProfileRuntime.capture().profileId,', ['0b edit engine seeds and selected assignments reach target only'])
    add('transfer-before-dialog-validation', '_transferOwnership', 'await _validateManagingAdmin(operationActor);', '', ['0b transfer refuses stale actor before showing dialog'], count=2, site=0)
    add('transfer-post-write-refresh', '_transferOwnership', AUTH_REFRESH, '', ['0b transfer refresh supports a later Save in same editor'])
    add('reset-post-write-refresh', '_removePinAsAdminLocally', AUTH_REFRESH, '', ['0b own Admin reset refresh supports later Save in same editor'])
    add('load-required-use', '_loadSetupOptions', '..add(ResourcePermission.use)', '', ['0b loaded download-only grant gains required use permission on Save'])
    add('edit-engine-preselection-all', '_loadSetupOptions', '.where((engine) => engine.assignedToTarget)', '.where((engine) => true)', ['0b edit engine seeds and selected assignments reach target only'])
    add('create-engine-preselection-none', '_loadSetupOptions', '? engines.map((engine) => engine.id)', '? <String>[]', ['0b create engine seeds and selected assignments reach target only'])
    add('copy-defaults-forced-on', '_save', 'copyDefaultsFromActive: snapshot.copyDefaults,', 'copyDefaultsFromActive: true,', ['0b create copy defaults switched off leaves actual appearance uncopied'])
    add('create-timeout-omitted', '_save', 'inactivityTimeoutMinutes: snapshot.inactivityMinutes == 0\n                  ? null\n                  : snapshot.inactivityMinutes,', 'inactivityTimeoutMinutes: null,', ['0b create writes timeout 5 and resume lock'])
    add('create-timeout-clear-omitted', '_save', 'clearInactivityTimeout: snapshot.inactivityMinutes == 0,', 'clearInactivityTimeout: false,', ['0b create writes timeout 0 and resume lock'])
    add('edit-timeout-omitted', '_save', 'inactivityTimeoutMinutes: expectedTimeout,', 'inactivityTimeoutMinutes: null,', ['0b edit writes timeout 5 and resume lock'])
    add('edit-timeout-clear-omitted', '_save', 'clearInactivityTimeout: expectedTimeout == null,', 'clearInactivityTimeout: false,', ['0b edit writes timeout 0 and resume lock'])
    add('create-lock-omitted', '_save', 'lockOnResume: snapshot.lockOnResume,', 'lockOnResume: false,', ['0b create writes timeout 5 and resume lock'], count=2, site=0)
    add('stored-role-always-defaults', '_setRole', 'existing != null && existing.role == role\n            ? existing.policy.enabled\n            : ProfilePolicy.defaultsFor(role).enabled', 'ProfilePolicy.defaultsFor(role).enabled', ['0b returning to stored role restores displayed and persisted split policy'])
    for field, feature in [('Downloads','downloads'), ('Remote','remoteControl')]:
        add('role-'+feature+'-seed-reset-omitted', '_setRole', '_seed'+field+' = _features.contains(ProfileFeature.'+feature+');', '', ['0b edit role change resets download and remote pair follow seeds'])
    add('phone-art-retains-picked-bytes', '_artTile', '_pendingAvatarBytes = null;', '', ['0b phone role art tile and connection persist after picked image'])
    add('phone-role-action-omitted', '_roleCard', 'onTap: _saving ? null : () => _setRole(role),', 'onTap: _saving ? null : () {},', ['0b phone role art tile and connection persist after picked image'])
    add('phone-connection-action-omitted', '_connectionRow', 'if (selected == true)', 'if (selected == true && PlatformUtil.isTelevision)', ['0b phone role art tile and connection persist after picked image'])
    add('phone-save-stays-enabled', 'build', 'onPressed: _saving ? null : _save,', 'onPressed: _save,', ['0b phone AppBar Save disables during real held PIN write'])
    add('edit-recovery-skipped', '_save', 'if (recoveryCode != null)', 'if (recoveryCode != null && widget.profile == null)', ['0b own Admin PIN refresh and edit recovery dialog precede pop'])
    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--original-root', type=Path, required=True)
    ap.add_argument('--parser-package', type=Path, required=True)
    args = ap.parse_args()
    assert '.dart_tool/edit_profile_parser/' in str(args.parser_package)
    from edit_profile_checker_fixtures import inputs
    from check_settings_moves import check
    from edit_profile_source_reader import validate
    from check_verbatim_moves import ROOT
    original, rows, config, leaves = inputs(args.parser_package)
    source = config['source']; target = args.original_root/source
    assert target.read_text() == original
    evidence = Path(subprocess.check_output(['git','rev-parse','--path-format=absolute','--git-common-dir'],cwd=ROOT,text=True).strip())/'refactor-evidence/edit_profile'
    output=evidence/'original-mutations.json'; records=json.loads(output.read_text())
    masked = [
        ('0b-save-create-start-core-masked', '_save', 'await _validateManagingAdmin(operationActor);', 0,
         ['0b Save create rejects '+x+' actor after loaded options' for x in ['stale','demoted']],
         'ProfileCreationService.createStaged first awaits actor.validate before registry.createProfile; stale revision is rejected before staging', 'createStaged calls actor.validate'),
        ('0b-transfer-before-write-core-masked', '_transferOwnership', 'await _validateManagingAdmin(operationActor);', 1,
         ['0b transfer revalidates after dialog and core masks omitted prewrite guard'],
         'ConnectionResourceService.transferOwnership first awaits actor.validate before resource reads, resealing or registry transfer', 'ConnectionResourceService.transferOwnership first await actor.validate'),
    ]
    guard=['flutter','test','--no-pub','--concurrency=1','--reporter=json','test/profiles/profile_source_guard_test.dart','--plain-name','profile editor keeps feature controls hidden behind one switch']
    for name, member, statement, site, cases, reason, marker in masked:
        node=leaves['_EditProfileScreenState.'+member];hits=list(re.finditer(re.escape(statement),node['text']));hit=hits[site]
        body=node['text'][:hit.start()]+node['text'][hit.end():]
        mutant=original[:node['start']]+body+original[node['end']:]
        command=['flutter','test','--no-pub','--concurrency=1','--reporter=json',TEST,'--name','^(?:'+'|'.join(re.escape(c) for c in cases)+')$']
        print('START '+name,flush=True)
        try:
            target.write_text(mutant)
            def run(cmd, tag):
                with (evidence/'mutations'/f'{name}-{tag}.jsonl').open('w') as out,(evidence/'mutations'/f'{name}-{tag}.stderr').open('w') as err:
                    r=subprocess.run(cmd,cwd=args.original_root,stdout=out,stderr=err)
                events=[json.loads(l) for l in (evidence/'mutations'/f'{name}-{tag}.jsonl').read_text().splitlines() if l.startswith('{')]
                return r,events
            r,events=run(command,'behavior')
            assert r.returncode==0,(name,r.returncode)
            demonstrations=[x['message'] for x in events if x['type']=='print' and marker in x.get('message','')]
            assert len(demonstrations)==len(cases)
            errors=check(original,{source:mutant},rows,source,args.parser_package,context_guard=True,config=config)
            assert errors
            try:validate(original,{source:mutant},rows,config,args.parser_package)
            except ValueError as error: reader=str(error)
            else:raise AssertionError('Reader accepted masked site')
            rejected,events=run(guard,'source')
            assertions=[x['error'] for x in events if x['type']=='error' and x.get('isFailure') and 'Expected:' in x.get('error','')]
            assert rejected.returncode!=0 and assertions
            record=dict(name=name,classification='S demonstrated core masking',reason=reason,member=member,site=site,before=statement,after='',cases=cases,command=guard,cwd=str(args.original_root),exit=rejected.returncode,behavior_command=command,behavior_exit=r.returncode,demonstrations=demonstrations,checker_errors=errors,reader_error=reader,assertions=assertions,proved=True,mutant_sha256=hashlib.sha256(mutant.encode()).hexdigest(),test_sha256=hashlib.sha256((args.original_root/TEST).read_bytes()).hexdigest())
            records['source_only']=[x for x in records['source_only'] if x['name']!=name]+[record]
            output.write_text(json.dumps(records,indent=2)+'\n')
            print('DONE '+name+' demonstrated + source assertion proved',flush=True)
        finally:target.write_text(original)
    return 0


if __name__=='__main__':
    raise SystemExit(main())
