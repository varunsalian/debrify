"""Per-declaration ORIGINAL, partial and completed ownership/physical proofs."""
import copy


def self_test(original, rows, config, leaves, package):
    from debrify_tv_checker_fixtures import layout
    from debrify_tv_source_reader import validate
    from check_settings_moves import all_nodes
    from check_verbatim_moves import parse
    source=config['source']
    assert validate(original,{source:original},rows,config,package)==[source]
    owners={r['original_name'] for r in rows if r['step'] in ['1','2']}
    selected=owners|{'_DebrifyTVScreenState._loadSettings'}
    partial=layout(original,rows,config,leaves,selected)
    assert len(validate(original,partial,rows,config,package))>=9
    # Mixed destination: loadSettings moves while its sibling members remain.
    mixed=layout(original,rows,config,leaves,owners|{'_DebrifyTVScreenState._loadSettings'})
    assert len(validate(original,mixed,rows,config,package))>=9
    import json
    from check_settings_moves import ROOT
    templates=json.loads((ROOT/config['sidecars']['scaffolding']).read_text())['templates']
    scaffold_only={source:original,**templates}
    assert validate(original,scaffold_only,rows,config,package)==[source]
    full_config={**config,'type_aliases':config['planned_type_aliases'],'completed_step':8}
    complete=layout(original,rows,full_config,leaves)
    assert len(validate(original,complete,rows,full_config,package))>40
    def reject(label,sources,cfg=full_config,expected=None):
        try:validate(original,sources,rows,cfg,package)
        except ValueError as error:
            if expected:assert expected in str(error),(label,error)
            print('TV reader '+label+': rejected');return
        raise AssertionError('Reader accepted '+label)
    row=next(r for r in rows if r['original_name']=='_DebrifyTVScreenState._startRandom')
    duplicate=copy.deepcopy(partial);duplicate[source]=original
    reject('duplicate ownership',duplicate,config,'Duplicate declaration ownership')
    missing=copy.deepcopy(partial);missing.pop(row['destination_file'])
    reject('missing ownership',missing,config,'Missing declaration ownership')
    reject('unregistered file',{**complete,config['feature']+'/models/extra.dart':''},expected='Unregistered extra')
    reject('scaffold declaring manifest leaf',{source:original,config['scaffolds'][0]:'class DebrifyTvSettingsState { bool startRandom = false; }'},config)
    reject('completed leaf retained',mixed,full_config)
    lookup=all_nodes(parse(complete,package,occurrence_bindings=True))
    for identity,before,after,label in [
        ('_DebrifyTVScreenState._launchTorboxOnAndroidTv','rethrow;','{}','deleted rethrow'),
        ('_DebrifyTVScreenState._watchWithTorbox','on NativePlayerSettingsUnavailable catch (error) {\n      _sections.feedback.showNativeSettingsFailure(error);\n    }','','deleted native catch'),
        ('_DebrifyTVScreenState._watch','      if (e is NativePlayerSettingsUnavailable) {','    if (e is NativePlayerSettingsUnavailable) {','failure block indentation'),
        ('_DebrifyTVScreenState._watch','_sections.feedback.showNativeSettingsFailure(e);','_sections.feedback.showSnack(e);','wrong failure member'),
    ]:
        row=next(r for r in rows if r['original_name']==identity);key=(row['destination_file'],row['destination_class'],row['new_name']);node=lookup[key]
        assert before in node['text'],(label,before)
        changed=copy.deepcopy(complete);changed[key[0]]=changed[key[0]][:node['start']]+node['text'].replace(before,after,1)+changed[key[0]][node['end']:]
        reject(label,changed)
    for path,template in templates.items():
        bad=template.replace('final ', 'late final ', 1)
        reject('scaffold initialization '+path, {source:original,**templates,path:bad},config,'Registered settings scaffold changed')
    sections=next(p for p in templates if p.endswith('debrify_tv_sections.dart'))
    bad=templates[sections].replace('feedback = DebrifyTvFeedback(deps)', 'feedback = buildFeedback(deps)', 1)
    reject('section built per access/build', {source:original,**templates,sections:bad},config,'Registered settings scaffold changed')
    print('TV reader ORIGINAL, partial, mixed, scaffold-only, simulated complete: PASS')
