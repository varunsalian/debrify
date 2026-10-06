#!/usr/bin/env python3
"""Build the complete manifest composition only inside .dart_tool and verify it.

Uses the actual checker and its frozen occurrence/callback configuration. New
scaffolding is token-frozen separately, never an exception for original bodies.
"""
import argparse
from collections import defaultdict
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from urllib.parse import urljoin


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--parser-package', type=Path, required=True)
    ap.add_argument('--freeze', action='store_true', help='write the reviewed new scaffolding inventory')
    args=ap.parse_args(); package=args.parser_package.resolve()
    assert '.dart_tool/edit_profile_parser/' in str(package)
    from check_verbatim_moves import ROOT, parse, ensure_parser_package
    ensure_parser_package(package.parent.parent, package)
    for dill in package.parent.rglob("*.dill"):dill.unlink()
    from edit_profile_checker_fixtures import inputs, moved_body
    from check_settings_moves import check, all_nodes, configured, tokens
    from edit_profile_source_reader import validate
    original,rows,config,leaves=inputs(package)
    assert subprocess.check_output(['git','diff',config['baseline'],'--','lib','pubspec.yaml','pubspec.lock'],cwd=ROOT)==b'', 'Probe requires the ORIGINAL application tree'
    scratch=ROOT/'.dart_tool/edit_profile_composition_probe'
    evidence=Path(subprocess.check_output(['git','rev-parse','--path-format=absolute','--git-common-dir'],cwd=ROOT,text=True).strip())/'refactor-evidence/edit_profile'
    evidence.mkdir(exist_ok=True,parents=True)
    if not (scratch/'lib').exists():
        shutil.copytree(ROOT/'lib',scratch/'lib')
        for file in ['analysis_options.yaml','pubspec.yaml','pubspec.lock']:
            shutil.copy2(ROOT/file,scratch/file)
    feature=scratch/config['feature']
    if feature.exists():shutil.rmtree(feature)
    feature.mkdir(parents=True)
    cfg=json.loads((ROOT/'.dart_tool/package_config.json').read_text())
    for pkg in cfg['packages']:
        pkg['rootUri']=scratch.as_uri()+'/' if pkg['name']=='debrify' else urljoin((ROOT/'.dart_tool/package_config.json').as_uri(),pkg['rootUri'])
    (scratch/'.dart_tool').mkdir(exist_ok=True)
    (scratch/'.dart_tool/package_config.json').write_text(json.dumps(cfg,indent=2)+'\n')
    # Strict imports and lint configuration on the eventual facade too.
    (scratch/'lib/screens/profiles/analysis_options.yaml').write_text('include: ../../features/analysis_options.yaml\n')
    config['callback_call_aliases']={a['original_name']:a['call'] for a in config['planned_constructor_forwarders']}
    sectionmap=json.loads((ROOT/'dev/tool/edit_profile_scaffolding.json').read_text())['section_map']
    ownermap=json.loads((ROOT/'dev/tool/edit_profile_scaffolding.json').read_text())['owner_map']
    base='lib/features/edit_profile/presentation/legacy_edit_profile/'
    sources={};groups=defaultdict(list);edits={}
    aliases=config['planned_type_aliases'];aliasmap={a['original_name']:a['alias'] for a in aliases}
    forwarders={a['original_name']:a['call'] for a in config['planned_constructor_forwarders']}
    # Scanner tokens prevent replacements in comments and literal text.
    def expose(text):
        prefix='class Probe {\n'; unit=parse({'body':prefix+text+'\n}'},package)['body']; tokens=unit['declarations'][0]['tokens']; changes=[]
        for i,t in enumerate(tokens):
            if t['comment'] or t['text'] not in aliasmap:continue
            value=forwarders.get(t['text'],aliasmap[t['text']]) if i+1<len(tokens) and tokens[i+1]['text']=='(' else aliasmap[t['text']]
            changes.append((t['offset']-len(prefix),len(t['text']),value))
        for at,size,value in reversed(changes):text=text[:at]+value+text[at+size:]
        return text
    for row in rows:
        node=leaves[row['original_name']]
        if row['destination_file']==config['source']:
            if node['owner']=='_EditProfileScreenState':edits[node['start']]=(node['end'],expose(moved_body(row,node,rows,config)))
            continue
        body=moved_body(row,node,rows,config)
        body=body.replace('_sections.access.accessGroups', 'accessGroups').replace('_sections.phone._featureLabel', '_featureLabel')
        if node['owner']=='_EditProfileScreenState':body=expose(body)
        groups[row['destination_file'],row['destination_class']].append(body)
        edits[node['start']]=(node['end'],'')
        if row['original_name']=='_EditProfileScreenState.build':
            edits[node['start']]=(node['end'],'@override\nWidget build(BuildContext context) => _sections.phone.build(context);')
    facade=original
    for at,(end,body) in sorted(edits.items(),reverse=True):facade=facade[:at]+body+facade[end:]
    facade=facade[facade.index('/// The profile create/edit form'):]
    idx=facade.index('  late ProfileAuthorizationContext _authorization')
    facade=facade[:idx]+'''  final EditProfileOwners _owners = EditProfileOwners();
  EditProfileSections? _composition;
  EditProfileSections get _sections => _composition ??= EditProfileSections(
    EditProfileDependencies(
      owners: _owners,
      sections: () => _composition!,
      registry: () => widget.registry,
      pins: () => widget.pins,
      profile: () => widget.profile,
      setupOptionsLoader: () => widget.setupOptionsLoader,
      context: () => context,
      mounted: () => mounted,
      setState: setState,
      readAuthorization: () => _authorization,
      writeAuthorization: (value) => _authorization = value,
      readShowFeaturePolicyControls: () => EditProfileScreen.showFeaturePolicyControls,
      policyFor: EditProfileScreen.policyFor,
    ),
  );
'''+facade[idx:]
    sources[config['source']]=facade
    for (file,owner),bodies in groups.items():
        body='\n'.join(bodies)
        if owner in [x['class'] for x in sectionmap.values()]:
            body='class '+owner+''' {
 final EditProfileDependencies _deps;
 '''+owner+'''(this._deps);
 EditProfileOwners get _owners => _deps.owners;
 EditProfileSections get _sections => _deps.sections();
'''+body+'\n}\n'
        elif owner:body='class '+owner+' {\n'+body+'\n}\n'
        if owner in [x['class'] for x in sectionmap.values()]:
            original_bodies='\n'.join(bodies)
            if '_owners' not in original_bodies:body=body.replace(' EditProfileOwners get _owners => _deps.owners;\n','')
            if '_sections' not in original_bodies:body=body.replace(' EditProfileSections get _sections => _deps.sections();\n','')
        sources[file]=body
    for a in aliases:sources[a['file']]+='\ntypedef '+a['alias']+' = '+a['original_name']+';\n'
    forwardtext=json.loads((ROOT/'dev/tool/edit_profile_scaffolding.json').read_text())['templates']['constructor forwarding']['source']
    sources['lib/features/edit_profile/presentation/edit_profile_tv_surfaces.dart']+=forwardtext
    sources[base+'edit_profile_owners.dart']='class EditProfileOwners {\n'+''.join(' final '+o['class']+' '+key+' = '+o['class']+'();\n' for key,o in ownermap.items())+'}\n'
    sources[base+'edit_profile_dependencies.dart']='''class EditProfileDependencies {
 final EditProfileOwners owners;
 final EditProfileSections Function() sections;
 final ProfileRegistry Function() registry;
 final ProfilePinService Function() pins;
 final UserProfile? Function() profile;
 final Future<(List<ConnectionResource>, List<ProfileEngineAssignment>)> Function()? Function() setupOptionsLoader;
 final BuildContext Function() context;
 final bool Function() mounted;
 final void Function(VoidCallback) setState;
 final ProfileAuthorizationContext Function() readAuthorization;
 final void Function(ProfileAuthorizationContext) writeAuthorization;
 final bool Function() readShowFeaturePolicyControls;
 final ProfilePolicy Function({required UserProfileRole role, required Set<ProfileFeature> selected, ProfilePolicy? existing, bool controlsShown}) policyFor;
 EditProfileDependencies({required this.owners,required this.sections,required this.registry,required this.pins,required this.profile,required this.setupOptionsLoader,required this.context,required this.mounted,required this.setState,required this.readAuthorization,required this.writeAuthorization,required this.readShowFeaturePolicyControls,required this.policyFor});
 ProfileAuthorizationContext get authorization => readAuthorization();
 set authorization(ProfileAuthorizationContext value) => writeAuthorization(value);
 bool get showFeaturePolicyControls => readShowFeaturePolicyControls();
}
'''
    sources[base+'edit_profile_sections.dart']='class EditProfileSections {\n'+''.join(' final '+s['class']+' '+key+';\n' for key,s in sectionmap.items())+' EditProfileSections(EditProfileDependencies deps)\n : '+',\n'.join(key+' = '+s['class']+'(deps)' for key,s in sectionmap.items())+';\n}\n'
    originalimports=original[:original.index('enum _TvProfileSection')]
    imports=[line.replace("import '../../", "import 'package:debrify/") for line in originalimports.splitlines() if line.startswith('import ')]
    generatedimports=["import 'package:debrify/"+file.removeprefix('lib/')+"';" for file in sources if file!=config['source']]
    for file,body in sources.items():
        # Add all needed candidates, then let analyzer identify unused imports.
        candidates=imports+[line for line in generatedimports if file.removeprefix('lib/') not in line]
        sources[file]='\n'.join(sorted(set(candidates)))+'\n\n'+body
        path=scratch/file;path.parent.mkdir(exist_ok=True,parents=True);path.write_text(sources[file])
    subprocess.run(['dart','format',str(feature),str(scratch/config['source'])],check=True,stdout=subprocess.DEVNULL)
    analyze=['dart','analyze','--format=machine',str(feature),str(scratch/config['source'])]
    # Remove only analyzer-identified unused/unnecessary imports in NEW import
    # lists. No original body or comment is changed to silence a diagnostic.
    for _ in range(3):
        result=subprocess.run(analyze,cwd=scratch,text=True,capture_output=True)
        removals=defaultdict(set)
        for line in result.stdout.splitlines():
            parts=line.split('|')
            if len(parts)>=8 and parts[2] in ['UNUSED_IMPORT','UNNECESSARY_IMPORT']:
                removals[Path(parts[3])].add(int(parts[4]))
        if not removals:break
        for path,lines in removals.items():
            if not path.is_relative_to(scratch):continue
            text=path.read_text().splitlines(keepends=True)
            for i in lines:assert text[i-1].startswith('import ')
            path.write_text(''.join(t for i,t in enumerate(text,1) if i not in lines))
        subprocess.run(['dart','format',str(feature),str(scratch/config['source'])],check=True,stdout=subprocess.DEVNULL)
    result=subprocess.run(analyze,cwd=scratch,text=True,capture_output=True)
    (evidence/'step0b-composition-analyze.txt').write_text(result.stdout+result.stderr)
    sources={file:(scratch/file).read_text() for file in sources}
    active=copy.deepcopy(config);active['type_aliases']=active['planned_type_aliases'];active['constructor_forwarders']=active['planned_constructor_forwarders']
    # Freeze every new composition leaf, independently from original leaves.
    with configured(active): nodes=all_nodes(parse(sources,package,occurrence_bindings=True))
    manifestkeys={(r['destination_file'],r['destination_class'],r['new_name']) for r in rows}
    scaffold=[]
    for (file,owner,name),node in nodes.items():
        if (file,owner,name) in manifestkeys or (file,'',owner) in manifestkeys:continue
        if file==config['source'] and (owner=='EditProfileScreen' or not owner or name in ['initState','dispose','build','_authorization']):continue
        if not owner and node.get('members'):continue
        scaffold.append(dict(file=file,owner=owner,name=name,tokens=tokens(node)))
    pin=ROOT/'dev/tool/edit_profile_composition_scaffolding.json'
    if args.freeze:pin.write_text(json.dumps({'scaffolds':scaffold,'scope':'0b complete scratch composition only; exact new scaffolding, no original-code exceptions'},indent=2)+'\n')
    else:assert json.loads(pin.read_text())['scaffolds']==scaffold,'Composition scaffolding differs from reviewed frozen tokens'
    active['sidecars']['scaffolding']='dev/tool/edit_profile_composition_scaffolding.json'
    active['plain_sections']=[dict(file=s['file'],owner=s['class']) for s in sectionmap.values()]
    (evidence/'step0b-composition-active-config.json').write_text(json.dumps(active,indent=2)+'\n')
    errors=check(original,sources,rows,config['source'],package,context_guard=True,config=active)
    (evidence/'step0b-composition-checker.txt').write_text('\n'.join(errors)+'\n' if errors else 'PASS: full 90-leaf manifest; occurrence bindings/substitutions, callbacks, public bytes, lifecycle, aliases and exact scaffolds\n')
    reader=None
    if not errors:reader=validate(original,sources,rows,active,package)==original
    facade=sources[config['source']]
    facadeunit=parse({'facade':facade},package)['facade']
    spans=[]
    for d in facadeunit['declarations']:
        if d['name']=='_EditProfileScreenState':
            for n in d['members']:spans.append(dict(member=d['name']+'.'+n['name'],lines=n['text'].count('\n')+1,start=facade[:n['start']].count('\n')+1,end=facade[:n['end']].count('\n')+1))
        else:spans.append(dict(member=d['name'],lines=d['text'].count('\n')+1,start=facade[:d['start']].count('\n')+1,end=facade[:d['end']].count('\n')+1))
    summary=dict(R=config['baseline'],command=['python3','dev/tool/edit_profile_composition_probe.py','--parser-package',str(package)],scratch=str(scratch),manifest_leaves=len(rows),moved_leaves=sum(r['destination_file']!=config['source'] for r in rows),checker_errors=errors,reader_original=reader,analyzer_command=analyze,analyzer_exit=result.returncode,facade_lines=len(facade.splitlines()),facade_spans=spans,file_lines={file:len(body.splitlines()) for file,body in sources.items()},source_sha256={file:hashlib.sha256(body.encode()).hexdigest() for file,body in sources.items()})
    (evidence/'step0b-composition-probe.json').write_text(json.dumps(summary,indent=2)+'\n')
    (evidence/'step0b-composition-sources.json').write_text(json.dumps(sources,indent=2)+'\n')
    print(json.dumps({k:summary[k] for k in ['manifest_leaves','moved_leaves','checker_errors','reader_original','analyzer_exit','facade_lines']},indent=2))
    return 1 if errors or any('|ERROR|' in l or l.startswith('ERROR|') for l in result.stdout.splitlines()) else 0


if __name__=='__main__':raise SystemExit(main())
