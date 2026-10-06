"""Real edit_profile config positives and independently mutated guard cases."""
import copy,json,re


def self_test(package):
    from debrify_tv_fixture_parse_cache import exact_parse_cache
    with exact_parse_cache(package):
        _self_test(package)
        _checkpoint_self_test(package)


def _self_test(package):
    from edit_profile_checker_fixtures import inputs,layout
    from edit_profile_source_reader import validate
    from check_settings_moves import check,all_nodes,configured
    from check_verbatim_moves import parse,ROOT
    from occurrence_field_bindings import failures
    original,rows,config,leaves=inputs(package)
    # Raw ORIGINAL/partial/complete syntax fixtures stay at the accepted 0b map;
    # the CLI separately checks live checkpoint wiring and exact scaffolds.
    import subprocess
    config=json.loads(subprocess.check_output(['git','show','2e46ad4216c496f7150e6c292c6e280e8efa8f87:dev/tool/edit_profile_checker_config.json'],cwd=ROOT,text=True))
    source=config['source']
    def verify(sources):
        try:return check(original,sources,rows,source,package,context_guard=True,config=config)
        except ValueError as error:return [str(error)]
    assert not verify({source:original})
    assert validate(original,{source:original},rows,config,package)==original
    sources=layout(original,rows,config,leaves)
    errors=verify(sources);assert not errors,'\n'.join(errors)
    assert validate(original,sources,rows,config,package)==original
    print('Edit profile real config ORIGINAL + moved syntax + reader positives: PASS')
    with configured(config):lookup=all_nodes(parse(sources,package,occurrence_bindings=True))
    def located(identity):
        r=next(r for r in rows if r['original_name']==identity)
        k=(r['destination_file'],r['destination_class'],r['new_name'])
        return (k,lookup[k]) if k in lookup else ((source,*identity.rsplit('.',1)),lookup[(source,*identity.rsplit('.',1))])
    count=0
    def reject(identity,label,change,base=sources):
        nonlocal count
        key,node=located(identity);body=change(node['text']);assert body!=node['text'],(identity,label)
        changed=dict(base);changed[key[0]]=changed[key[0]][:node['start']]+body+changed[key[0]][node['end']:]
        assert verify(changed),'Checker accepted '+label
        try:validate(original,changed,rows,config,package)
        except ValueError:pass
        else:raise AssertionError('Reader accepted '+label)
        count+=1;print('Edit profile '+label+': checker + reader rejected')
    state='_EditProfileScreenState.'
    for identity,before,after,label in [
        ('_setRole','_owners.form.role = role','role = role','role parameter capture'),
        ('_loadSetupOptions','_owners.access.resources = resources','resources = resources','resources local capture'),
        ('_loadResources','_owners.access.resources = resources','resources = resources','reload resources capture'),
        ('_defaultResourcePermissions','features ?? _owners.form.features','features ?? features','features parameter capture'),
        ('_focusTvContent','_owners.tv.tvSection','section','section parameter capture'),
        ('_loadSetupOptions','_owners.access.engines = engines','engines = engines','engines local capture'),
        ('_loadSetupOptions','_deps.profile()','_deps.profile','missing widget getter invocation'),
        ('_loadSetupOptions','_deps.setupOptionsLoader()!()','_deps.setupOptionsLoader!()','nullable loader invocation lost'),
        ('_save','_deps.authorization = operationActor','authorization = operationActor','authorization setter cached field'),
        ('_save','_deps.policyFor(','localPolicyFor(','local policy rule copy'),
        ('_save','_deps.profile()?.policy','cachedProfile?.policy','cached profile read'),
        ('_loadSetupOptions','_deps.registry()','_deps.profile()','wrong widget substitution'),
        ('_removePinAsAdminLocally','_deps.pins()','cachedPins','cached PIN dependency'),
        ('_save','_deps.showFeaturePolicyControls','localShowControls','cached static flag'),
        ('_validateManagingAdmin','context.validate','_deps.context().validate','authorization context captured by State context'),
        ('_transferOwnership','Navigator.pop(context, false)','Navigator.pop(_deps.context(), false)','dialog context captured'),
        ('_buildTvSectionRail','builder: (context, constraints)','builder: (otherContext, constraints)','builder lexical context changed'),
        ('_save','var operationActor = _deps.authorization;','var operationActor = cachedActor;','actor cached before save'),
    ]:
        reject(state+identity,label,lambda s,b=before,a=after:s.replace(b,a,1))
    # A balanced local/field exchange must not survive aggregate identifier counts.
    reject(state+'_loadSetupOptions','balanced field/local capture',lambda s:s.replace('_owners.access.resources = resources','resources = _owners.access.resources',1))
    reject(state+'_authorization','lazy actor becomes eager',lambda s:s.replace('late ', '',1))
    reject(state+'dispose','first two owned disposals reordered',lambda s:s.replace('_owners.tv.tvContentFocus.dispose();','SWAP;').replace('_owners.tv.tvBackFocus.dispose();','_owners.tv.tvContentFocus.dispose();').replace('SWAP;','_owners.tv.tvBackFocus.dispose();'))
    reject(state+'dispose','last two controller disposals reordered',lambda s:re.sub(r'(_owners.form.name.dispose\(\);)(\s*)(_owners.form.pin\s*\.\.clear\(\)\s*\.\.dispose\(\);)',r'\3\2\1',s))
    reject(state+'initState','setup load before seeds',lambda s:s.replace('_sections.setup.loadSetupOptions();','').replace('_owners.form.seedDownloads =','_sections.setup.loadSetupOptions();\n    _owners.form.seedDownloads =',1))
    reject(state+'_policyTouched','field documentation dropped',lambda s:re.sub(r'(?m)^\s*///[^\n]*\n','',s))
    reject(state+'_connectionRow','in-list comment reworded',lambda s:s.replace('Sharing is BINARY now','Sharing is binary now',1))
    # Actual per-occurrence callback negatives, including closure callbacks.
    targets=['_save','_pickAvatarImage','_removePinAsAdmin','_loadSetupOptions','_showDiagnostics','_returnToTvRail','_handleTvRailKey','_selectResource','_deselectResource','_transferOwnership']
    for r in rows:
        if not r['original_name'].startswith(state):continue
        key,node=located(r['original_name']);body=node['text']
        for target in targets:
            tr=next(t for t in rows if t['original_name']==state+target)
            path=next(p for p,c in config['receiver_paths'].items() if c==tr['destination_class'])
            expression=path+'.'+tr['new_name']
            hits=list(re.finditer(re.escape(expression)+r'\b',body))
            # Match every occurrence in rendering leaves and editable.forEach.
            if r['scope'] not in ['phone','phoneParts','tvEditor','tvProfile','tvPanes','access']:continue
            for ordinal,hit in enumerate(hits):
                for label,replacement in [('wrapper','(() => '+expression+'())'),('receiver','otherSection.'+tr['new_name']),('member',path+'.'+({'_removePinAsAdmin':'_removePinAsAdminLocally','_selectResource':'deselectResource','_deselectResource':'selectResource'}.get(target,'wrongMember'))),('cached','cachedTearOff')]:
                    reject(r['original_name'],r['original_name']+' callback '+target+' #'+str(ordinal)+' '+label,
                           lambda s,h=hit,v=replacement:s[:h.start()]+v+s[h.end():])
    # Getter/setter ordering and literal-safe source: missing/duplicate leaves fail.
    key,node=located(state+'_setRole')
    reject(state+'_setRole','missing declaration',lambda s:'')
    reject(state+'_setRole','duplicate declaration',lambda s:s+'\n'+s)
    for owner in ['EditProfileFormState','EditProfileTvFocusState','EditProfileAccessState']:
        key=next(k for k in lookup if k[1]==owner);node=lookup[key]
        changed=dict(sources);changed[key[0]]=changed[key[0]][:node['start']]+node['text']+'\nObject injected = role;'+changed[key[0]][node['end']:]
        with configured(config):bad=all_nodes(parse(changed,package,occurrence_bindings=True))
        assert any('Bare owner field reference' in e for e in failures(leaves,bad,rows,source,config,members=set(),package=package))
        assert verify(changed)
        try:validate(original,changed,rows,config,package)
        except ValueError:pass
        else:raise AssertionError('Reader accepted bare record field')
        count+=1
    # Optional exact syntax scaffolds do not create the step-0b composition.
    sidecar=json.loads((ROOT/'dev/tool/edit_profile_scaffolding.json').read_text())
    templated=dict(sources)
    templated.update({v['file']:v['source'] for v in sidecar['templates'].values()})
    assert not verify(templated),verify(templated)
    assert validate(original,templated,rows,config,package)==original
    for label,before,after in [
        ('eager owners','form = EditProfileFormState();','form = cachedForm;'),
        ('eager owners','final EditProfileFormState form = EditProfileFormState();\n final EditProfileTvFocusState tv = EditProfileTvFocusState();','final EditProfileTvFocusState tv = EditProfileTvFocusState();\n final EditProfileFormState form = EditProfileFormState();'),
        ('authorization pair','readAuthorization()','cachedAuthorization'),
        ('authorization pair','writeAuthorization(value)','eagerAuthorization = value'),
        ('lazy field forwarding','() => state._authorization','() => cachedAuthorization'),
        ('lazy field forwarding','state._authorization = value','eagerAuthorization = value'),
        ('constructor forwarding','key: key','key: null'),
        ('constructor forwarding','bool selected = false','bool selected = true'),
        ('constructor forwarding','EditProfileTvActionSurface(','_TvActionSurface('),
    ]:
        template=sidecar['templates'][label];changed=dict(templated)
        changed[template['file']]=changed[template['file']].replace(before,after,1)
        assert changed!=templated
        assert verify(changed),'accepted '+label
        try:validate(original,changed,rows,config,package)
        except ValueError:pass
        else:raise AssertionError('Reader accepted '+label)
        count+=1;print('Edit profile '+label+' changed: checker + reader rejected')
    # State read changed to a bare context, builder read to State, and vice versa.
    for member,before,after in [
        ('_showRecoveryCode','context: _deps.context()','context: context'),
        ('_buildTvEditor','Theme.of(context)','Theme.of(_deps.context())'),
        ('_transferOwnership','Navigator.pop(context, true)','Navigator.pop(_deps.context(), true)'),
        ('_save','var operationActor = _deps.authorization;','var operationActor = cachedActor;'),
    ]:
        if before==after:continue
        reject(state+member,'context identity '+member,lambda s,b=before,a=after:s.replace(b,a,1))
    reject(state+'_save','actor read hoisted above avatar preparation',lambda s:s.replace('var operationActor = _deps.authorization;', '',1).replace('if (snapshot.pendingAvatarBytes != null)', 'var operationActor = _deps.authorization;\n      if (snapshot.pendingAvatarBytes != null)',1))
    reject(state+'_save','authorization write moved across await',lambda s:s.replace('_deps.authorization = operationActor;','',1).replace('await _showRecoveryCode(snapshot.name, recoveryCode);', 'await _showRecoveryCode(snapshot.name, recoveryCode);\n        _deps.authorization = operationActor;',1))
    # Every physical callback receiver is tested against another instance of
    # the SAME class, through the resolver independently of verbatim tokens.
    from torbox_callback_identity import check_callback_identities
    callback_count=0
    for r in rows:
        if not r['original_name'].startswith(state) or r['scope'] not in ['phone','phoneParts','tvEditor','tvProfile','tvPanes','access']:continue
        key,node=located(r['original_name'])
        expressions={}
        for spec in config.get('callback_identities',[]):
            if not any(site['member']==r['original_name'] for site in spec['sites']):continue
            target_row=next((x for x in rows if x['original_name']==spec.get('callback_member')),None)
            if target_row:
                path=next(p for p,c in config['receiver_paths'].items() if c==target_row['destination_class'])
                expressions[path+'.'+target_row['new_name']]=target_row['new_name']
            else:expressions['_owners.access.selectedEngines.clear']='clear'
        for expression,name in expressions.items():
            for hit in re.finditer(re.escape(expression)+r'\b',node['text']):
                changed=dict(sources);body=node['text'][:hit.start()]+'sameClassOther.'+name+node['text'][hit.end():]
                changed[key[0]]=changed[key[0]][:node['start']]+body+changed[key[0]][node['end']:]
                independent=copy.deepcopy(config)
                independent['callback_receiver_aliases']['sameClassOther']= '$Other.sameClassInstance'
                with configured(independent):bad=all_nodes(parse(changed,package,occurrence_bindings=True))
                assert check_callback_identities(bad,rows,source,independent),(r['original_name'],expression)
                assert verify(changed)
                try:validate(original,changed,rows,config,package)
                except ValueError:pass
                else:raise AssertionError('Reader accepted same-class callback receiver')
                callback_count+=1
    # Every setState/onChanged callback expression is a distinct tested boundary.
    from torbox_callback_identity import argument_ranges
    for r in rows:
        if not r['original_name'].startswith(state):continue
        key,node=located(r['original_name']);values=[t['text'] for t in node['tokens']]
        for call in ['setState','SwitchListTile','DropdownButtonFormField','_TvAutoLockField']:
            for ordinal,spans in enumerate(argument_ranges(values,call)):
                for a,b in spans:
                    expr=values[a:b]
                    if call!='setState':
                        if expr[:2]!=['onChanged',':']:continue
                        a+=2
                    start=node['tokens'][a]['offset']-node['start'];end=node['tokens'][b-1]['offset']-node['start']+len(values[b-1])
                    reject(r['original_name'],r['original_name']+' '+call+' callback #'+str(ordinal),lambda s,a=start,b=end:s[:a]+'cachedTearOff'+s[b:])
    print('Edit profile same-class callback identity negatives: '+str(callback_count))
    print('Edit profile checker + reader negatives proved: '+str(count+callback_count))


def _checkpoint_self_test(package):
    """Check the live checkpoint and reject changes to its exact new wiring."""
    from edit_profile_checker_fixtures import inputs
    from edit_profile_source_reader import validate
    from check_settings_moves import check
    from check_verbatim_moves import ROOT
    original,rows,config,leaves=inputs(package)
    if config.get('completed_step',0)<1:return
    sources={config['source']:(ROOT/config['source']).read_text()}
    sources.update({p.relative_to(ROOT).as_posix():p.read_text()
                    for p in (ROOT/config['feature']).rglob('*.dart')})
    assert not check(original,sources,rows,config['source'],package,
                     context_guard=True,config=config)
    assert validate(original,sources,rows,config,package)==original
    base='lib/features/edit_profile/presentation/legacy_edit_profile/'
    cases=[('typedef enum','lib/features/edit_profile/models/edit_profile_tv_section.dart',
            'typedef EditProfileTvSection = _TvProfileSection;',
            'typedef EditProfileTvSection = bool;'),
           ('surface default','lib/features/edit_profile/presentation/edit_profile_tv_surfaces.dart',
            'bool selected = false,','bool selected = true,')]
    if config['completed_step']>=2:
        cases += [
            ('cached State context',config['source'],'context: () => context,','context: () => cachedContext,'),
            ('composition reconstructed',config['source'],'_composition ??= EditProfileSections(',
             '_composition = EditProfileSections('),
            ('authorization write cached',config['source'],'writeAuthorization: (value) => _authorization = value,',
             'writeAuthorization: (value) => cachedAuthorization = value,'),
            ('eager owner order',base+'edit_profile_owners.dart',
             'final EditProfileFormState form = EditProfileFormState();\n  final EditProfileTvFocusState tv = EditProfileTvFocusState();',
             'final EditProfileTvFocusState tv = EditProfileTvFocusState();\n  final EditProfileFormState form = EditProfileFormState();')]
    for label,file,before,after in cases:
        assert before in sources[file],label
        changed=dict(sources);changed[file]=changed[file].replace(before,after,1)
        assert check(original,changed,rows,config['source'],package,
                     context_guard=True,config=config),'Checkpoint accepted '+label
        try:validate(original,changed,rows,config,package)
        except ValueError:pass
        else:raise AssertionError('Checkpoint reader accepted '+label)
        print('Edit profile live checkpoint '+label+': checker + reader rejected')
    extra=0
    if config['completed_step']>=6:
        completion=[]
        for label,file in [('facade missing',config['source']),
                           ('scaffold-only file missing',base+'edit_profile_owners.dart')]:
            changed=dict(sources);del changed[file]
            completion.append((label,changed))
        changed=dict(sources)
        at=changed[config['source']].rfind('\n}')
        assert at>=0
        changed[config['source']]=(changed[config['source']][:at]+'\n'+
            leaves['_EditProfileScreenState._save']['text']+'\n'+
            changed[config['source']][at:])
        completion.append(('completed original leaf retained',changed))
        for label,changed in completion:
            try:
                errors=check(original,changed,rows,config['source'],package,
                             context_guard=True,config=config)
            except ValueError as error:
                errors=[str(error)]
            assert errors,'Completion accepted '+label
            try:validate(original,changed,rows,config,package)
            except ValueError:pass
            else:raise AssertionError('Completion reader accepted '+label)
            extra+=1
            print('Edit profile completion '+label+': checker + reader rejected')
        from edit_profile_architecture_test import self_test as architecture_self_test
        architecture_self_test()
    print('Edit profile live checkpoint wiring: PASS; '+str(len(cases)+extra)+' negatives')
