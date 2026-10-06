#!/usr/bin/env python3
"""Reproduce assertion-failing editor mutations in the owned ORIGINAL copy.

No mutation changes a profile service. Inputs are checkpoint tests; the sole
application write is restored from R in finally, before another mutation starts.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

SOURCE = 'lib/screens/profiles/edit_profile_screen.dart'
TESTS = 'test/features/edit_profile/presentation/legacy_edit_profile/'


def specifications():
    result = []
    def add(name, member, before, after, cases, file='save', count=1, framework_assertion=None):
        result.append(dict(name=name, member=member, before=before, after=after,
                           cases=cases, file=TESTS+'edit_profile_'+file+'_test.dart', count=count,
                           framework_assertion=framework_assertion))
    add('create-avatar-seed', 'initState', "? 'child' : 'person'", "? 'child' : 'child'", ['R create seeds member defaults and person avatar'])
    add('stored-lock-seed', 'initState', 'profile?.lockOnResume ?? false', 'false', ['R edit seeds stored lock timeout avatar and child fallback'])
    add('nullable-kid-avatar', 'initState', "profile?.role == UserProfileRole.child ? 'child' : 'person'", "false ? 'child' : 'person'", ['R nullable legacy Kid avatar uses child fallback'])
    add('disposed-load-calls-supplied-loader', '_loadSetupOptions', 'await widget.setupOptionsLoader!()', '(<ConnectionResource>[], <ProfileEngineAssignment>[])', ['R disposed held setup publishes nothing'])
    add('disposed-load-mounted-guards-removed', '_loadSetupOptions', 'if (!mounted) return;', '', ['R disposed held setup publishes nothing'], count=2,
        framework_assertion='setState() called after dispose(): _EditProfileScreenState')
    add('stale-load-recaptures-active-admin', '_loadSetupOptions', '_authorization', '(await ProfileAuthorizationContext.capture(widget.registry))', ['R stale authorization load error refuses save'], count=3)
    add('load-admin-validation', '_loadSetupOptions', 'await _validateManagingAdmin(_authorization);', '', ['R non-admin actor load error refuses save'])
    add('empty-name-guard', '_save', 'if (_saving || _name.text.trim().isEmpty) return;', 'if (_saving) return;', ['R empty name is a no-op'])
    add('options-loading-guard', '_save', 'if (_resources == null || _engines == null || _setupLoadError != null)', 'if (false)', ['R held options reports loading before writes'])
    add('pin-lower-bound', '_save', r"RegExp(r'^\d{4,8}$')", r"RegExp(r'^\d{3,8}$')", ['R short PIN refuses save'])
    add('create-name-target', '_save', 'name: snapshot.name,', "name: 'Wrong profile name',", ['O create publishes fields and pops true'], count=2)
    add('recovery-barrier', '_showRecoveryCode', 'barrierDismissible: false', 'barrierDismissible: true', ['O create PIN recovery precedes pop'])
    add('rollback-condition-inverted', '_save', 'if (!stagedPublished &&', 'if (stagedPublished &&', ['O create PIN failure rolls back rows and avatar bytes'])
    add('early-staged-publication', '_save', 'var stagedPublished = false;', 'var stagedPublished = true;', ['O create completion failure rolls back rows and avatar bytes'])
    add('publication-completion-omitted', '_save', 'await creation.completeStaged(\n              profileId: staged.id,\n              actor: operationActor,\n            );', "throw StateError('mutation omitted completion');", ['O published checkpoint failures 1 retain or finalize intent'])
    add('post-publication-intent-cleared-on-failure', '_save', 'Error.throwWithStackTrace(error, stackTrace);', 'await ProfileAvatarMutation.complete(staged.id);\n          Error.throwWithStackTrace(error, stackTrace);', ['O published checkpoint failures 2 retain or finalize intent'])
    add('avatar-finalization-no-longer-swallowed', '_save', 'await ProfileAvatarMutation.complete(staged.id);\n            } catch (_) {', 'await ProfileAvatarMutation.complete(staged.id);\n            } catch (_) {\n              rethrow;', ['O published checkpoint failures 0 retain or finalize intent'])
    add('stored-policy-ignored', '_save', 'existing: widget.profile?.policy,', 'existing: null,', ['O identity edit preserves stored split policy on target'])
    add('role-change-authorship-ignored', '_save', '(widget.profile != null && widget.profile!.role != snapshot.role)', 'false', ['O role change saves defaults and clamped Kid policy'])
    add('pair-follow-inverted', '_save', 'if (!moved) return;', 'if (moved) return;', ['O touched Pages downloads pair follows moved toggle'])
    add('kid-remote-authorship-lost', '_buildTvPagesSection', '_policyTouched = true;', '_policyTouched = false;', ['O touched Kid Remote clamps paired transfer before persisted comparison'])
    add('double-save-guard', '_save', 'if (_saving || _name.text.trim().isEmpty) return;', 'if (_name.text.trim().isEmpty) return;', ['O own-profile reload exactly once and double Save accepted once'])
    add('save-focus-restore-removed', '_save', '_restoreTvSaveFocus();', '', ['R held TV save locks focus pointer and pop then failure restores Save'], count=2)
    add('saving-error-reset-removed', '_save', 'setState(() => _saving = false);', '', ['R held TV save locks focus pointer and pop then failure restores Save'], count=2)
    add('grant-target-is-active-profile', '_applyResourceGrants', 'targetProfileId: targetProfileId,', 'targetProfileId: ProfileRuntime.capture().profileId,', ['O target grants engines identity and lock leave admin unchanged'], file='access', count=2)
    add('derived-write-remote-mask', '_defaultResourcePermissions', 'ResourcePermission.writeRemote,', 'ResourcePermission.download,', ['O newly selected mask derives use download and writeRemote from target policy'], file='access')
    add('grant-refresh-removed', '_applyResourceGrants', 'operationActor = await _refreshSameManagingAdmin(\n          operationActor.profileId,\n        );', '', ['O grant refresh supports active Admin singleton rebinding'], file='access', count=2)
    add('session-refresh-check-removed', '_refreshSameManagingAdmin', 'if (refreshed.profileId != initiatingProfileId)', 'if (false)', ['O session switch after PIN keeps earlier writes and rejects grants engines'], file='access')
    add('snapshot-selection-reread', '_applyResourceGrants', 'snapshot.selectedResources.contains(resource.id)', '_selectedResources.contains(resource.id)', ['O captured selection snapshot survives callback after PIN await'], file='access')
    add('stored-mask-overwritten-on-reselect', '_selectResource', '_resourcePermissions.putIfAbsent(\n      resource.id,\n      () => _defaultResourcePermissions(_role),\n    );', '_resourcePermissions[resource.id] = _defaultResourcePermissions(_role);', ['O existing mask no churn and reselect keeps stored permission'], file='access')
    add('borrower-revoke-omitted', '_applyResourceGrants', 'await service.revokeGrant(\n          actor: operationActor,\n          targetProfileId: targetProfileId,\n          resourceId: resource.id,\n        );', '', ['O deselect revokes borrower grant'], file='access')
    add('owned-row-editable', '_connectionRow', 'resource.ownerProfileId != widget.profile?.id', 'true', ['O owned connection cannot toggle or revoke and read-only TV row focuses'], file='access')
    add('owned-row-revoke-allowed', '_applyResourceGrants', 'resource.ownerProfileId != targetProfileId', 'true', ['O formerly editable callback cannot revoke newly owned connection'], file='access')
    add('singleton-rival-selection-kept', '_selectResource', '_selectedResources.remove(other.id);', '', ['R singleton rivals deselect through group All and None'], file='access')
    add('engine-none-does-not-clear', '_buildEngineGroup', 'setState(_selectedEngines.clear)', 'setState(() {})', ['O engine All then None persists empty independent generation'], file='access')
    add('own-engines-editable', '_buildEngineGroup', 'final ownEditor = widget.profile?.id == _authorization.profileId;', 'final ownEditor = false;', ['R own editor engine controls are read-only'], file='access')
    add('transfer-target-swapped', '_transferOwnership', 'newOwnerProfileId: target.id,', 'newOwnerProfileId: operationActor.profileId,', ['O transfer confirm preserves owner and result'], file='access')
    add('transfer-cancel-ignored', '_transferOwnership', 'if (confirmed != true) return;', '', ['O transfer cancel preserves owner and result'], file='access')
    add('transfer-rejection-feedback-omitted', '_transferOwnership', "Text('Connection could not be transferred')", "Text('Connection transfer error')", ['O transfer session preserves owner and result'], file='access')
    add('pin-reset-feedback', '_removePinAsAdminLocally', "Text('PIN protection removed')", "Text('PIN reset complete')", ['O admin PIN reset succeeds with correct snackbar'], file='access')
    add('pin-reset-failure-feedback', '_removePinAsAdminLocally', "Text('PIN protection was not changed')", "Text('PIN reset failed')", ['O admin PIN reset fails with correct snackbar'], file='access')
    add('pin-reset-visible-without-profile', '_buildTvLockSection', 'if (widget.profile?.hasPin == true ||', 'if (true || widget.profile?.hasPin == true ||', ['R PIN reset absent without PIN or reset requirement'], file='access')
    add('picker-declared-limit', '_pickAvatarImage', 'if (file.size > ProfileAvatarIngest.maxInputBytes)', 'if (false)', ['R picker declared rejects without preview'], file='avatar')
    add('picker-inline-limit', '_readPickedBytes', 'if (inline.length > ProfileAvatarIngest.maxInputBytes)', 'if (false)', ['R picker inline rejects without preview'], file='avatar')
    add('picker-stream-limit', '_readPickedBytes', 'if (length > ProfileAvatarIngest.maxInputBytes - chunk.length)', 'if (false)', ['R picker streamed rejects without preview'], file='avatar')
    add('picker-unreadable-feedback', '_pickAvatarImage', "Text('That image could not be opened.')", "Text('That file could not be read.')", ['R picker unreadable rejects without preview'], file='avatar')
    add('picker-platform-feedback', '_pickAvatarImage', "Text('The image picker is not available.')", "Text('That image could not be opened.')", ['R picker platform rejects without preview'], file='avatar')
    add('picker-missing-path-feedback', '_readPickedBytes', "throw const ProfileAvatarRejected('That file could not be read.');", "throw StateError('mutation missing path');", ['R picker missing rejects without preview'], file='avatar')
    add('picker-preview-not-published', '_pickAvatarImage', '_pendingAvatarBytes = prepared.bytes', '_pendingAvatarBytes = null', ['R valid PNG preview discards without disk publication'], file='avatar')
    add('picked-avatar-key-not-published', '_save', 'preparedAvatar?.avatar.format() ?? snapshot.avatarKey', 'snapshot.avatarKey', ['O picked PNG create publishes file key and bytes', 'O picked PNG edit publishes file key and bytes'], file='avatar')
    add('late-picker-saving-check-removed', '_pickAvatarImage', 'if (!mounted || _saving) return;', 'if (!mounted) return;', ['R picker started before held save drops late bytes'], file='avatar')
    add('phone-form-padding', 'build', 'padding: const EdgeInsets.all(20)', 'padding: const EdgeInsets.all(24)', ['R ORIGINAL golden phone_create', 'R ORIGINAL golden phone_edit'], file='goldens')
    add('tv-rail-width', '_buildTvSectionRail', 'width: 200,', 'width: 220,', ['R ORIGINAL golden tv_profile', 'R ORIGINAL golden tv_access'], file='goldens')
    add('policy-reload-condition-widened', '_save', 'widget.profile?.id == ProfileRuntime.capture().profileId', 'widget.profile != null', ['O identity edit preserves stored split policy on target'])
    from edit_profile_review_mutations import specifications as review_specs
    result.extend(review_specs())
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--original-root', type=Path, required=True)
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--only', action='append')
    args = parser.parse_args()
    from check_verbatim_moves import ROOT, parse
    config = json.loads((ROOT/'dev/tool/edit_profile_checker_config.json').read_text())
    if '.dart_tool/edit_profile_parser/' not in str(args.parser_package):
        parser.error('use the worktree-isolated edit_profile parser')
    evidence = Path(subprocess.check_output(['git','rev-parse','--path-format=absolute','--git-common-dir'],cwd=ROOT,text=True).strip())/'refactor-evidence/edit_profile'
    evidence.mkdir(parents=True,exist_ok=True)
    output = evidence/'original-mutations.json'
    previous = json.loads(output.read_text()) if output.exists() else {'R':config['baseline'],'behavioral':[],'source_only':[]}
    original = subprocess.check_output(['git','show',config['baseline']+':'+SOURCE],cwd=ROOT)
    target = args.original_root/SOURCE
    assert target.read_bytes()==original
    assert subprocess.check_output(['git','diff',config['baseline'],'--','lib','pubspec.yaml','pubspec.lock'],cwd=args.original_root)==b''
    nodes = next(d for d in parse({'original':original.decode()},args.parser_package)['original']['declarations'] if d['name']=='_EditProfileScreenState')['members']
    members = {n['name']:n for n in nodes}
    directory = evidence/'mutations';directory.mkdir(exist_ok=True)
    for spec in specifications():
        if args.only and spec['name'] not in args.only:continue
        node = members[spec['member']]
        assert node['text'].count(spec['before'])==spec['count'],(spec['name'],node['text'].count(spec['before']))
        if 'site' in spec:
            sites = list(re.finditer(re.escape(spec['before']), node['text']))
            hit = sites[spec['site']]
            changed = node['text'][:hit.start()] + spec['after'] + node['text'][hit.end():]
        else:
            changed = node['text'].replace(spec['before'],spec['after'])
        mutant = original.decode()[:node['start']]+changed+original.decode()[node['end']:]
        command = ['flutter','test','--no-pub','--concurrency=1','--reporter=json',spec['file'],'--name','^(?:'+'|'.join(re.escape(c) for c in spec['cases'])+')$']
        print('START '+spec['name'],flush=True)
        try:
            target.write_text(mutant)
            with (directory/(spec['name']+'.jsonl')).open('w') as out,(directory/(spec['name']+'.stderr')).open('w') as err:
                result = subprocess.run(command,cwd=args.original_root,stdout=out,stderr=err)
            events = [json.loads(l) for l in (directory/(spec['name']+'.jsonl')).read_text().splitlines() if l.startswith('{')]
            identities = {x['test']['id']:x['test']['name'] for x in events if x['type']=='testStart'}
            failed = {identities[x['testID']] for x in events if x['type']=='testDone' and x.get('result') in ('error','failure') and not x.get('hidden')}
            def assertion(message):
                if 'TestFailure' in message and 'Expected:' in message:
                    return True
                if 'The following assertion' in message and 'Pixel test failed' in message:
                    return True
                # The held-disposal case exercises Flutter's explicit State
                # lifecycle assertion, not a setup error or generic exception.
                marker = spec.get('framework_assertion')
                return bool(marker and 'The following assertion was thrown' in message
                            and marker in message and 'State.setState.<anonymous closure>' in message
                            and '_EditProfileScreenState._loadSetupOptions' in message)
            messages = {case:[x['message'] for x in events if x['type']=='print' and identities.get(x.get('testID'))==case and assertion(x.get('message',''))] for case in spec['cases']}
            assertions = {case:[m.split('When the exception')[0] for m in ms] for case,ms in messages.items() if ms}
            record = dict(spec,command=command,cwd=str(args.original_root),exit=result.returncode,failed=sorted(failed),assertions=assertions,mutant_sha256=hashlib.sha256(mutant.encode()).hexdigest(),original_sha256=hashlib.sha256(original).hexdigest(),test_sha256=hashlib.sha256((args.original_root/spec["file"]).read_bytes()).hexdigest(),proved=result.returncode!=0 and set(spec['cases'])<=failed and set(spec['cases'])<=set(assertions))
            previous['behavioral']=[r for r in previous['behavioral'] if r['name']!=spec['name']]+[record]
            output.write_text(json.dumps(previous,indent=2)+'\n')
            print('DONE '+spec['name']+' proved='+str(record['proved']),flush=True)
        finally:
            target.write_bytes(original)
            import shutil
            for feedback in (args.original_root/'test').rglob('failures'):
                if feedback.is_dir():
                    destination = directory/(spec['name']+'-golden-feedback')
                    if destination.exists():shutil.rmtree(destination)
                    shutil.move(str(feedback),destination)
    assert target.read_bytes()==original
    return 0 if all(x['proved'] for x in previous['behavioral']) else 1


if __name__=='__main__':
    raise SystemExit(main())
