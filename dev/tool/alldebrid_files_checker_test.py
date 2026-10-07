#!/usr/bin/env python3
"""Real AllDebrid config/declarations: direct identity and occurrence negatives."""
import copy
import csv
import json
import re
import subprocess
from pathlib import Path


def source_reader_self_test(ROOT, original):
    """Normalize a retained real facade body after its fields move; no masking."""
    import tempfile
    with tempfile.TemporaryDirectory(prefix='alldebrid-reader-', dir=ROOT / '.dart_tool') as directory:
        fixture = Path(directory)
        source = fixture / 'lib/screens/alldebrid/alldebrid_files_screen.dart'
        source.parent.mkdir(parents=True)
        source.write_text(original)
        (fixture / 'dev/tool').mkdir(parents=True)
        for name in ['alldebrid_files_manifest.tsv', 'alldebrid_files_checker_config.json', 'alldebrid_files_context_exceptions.json', 'alldebrid_files_original_bodies.json']:
            (fixture / 'dev/tool' / name).write_bytes((ROOT / 'dev/tool' / name).read_bytes())
        reader = (ROOT / 'test/support/alldebrid_files_source.dart').as_uri()
        probe = fixture / 'probe.dart'
        probe.write_text("import 'dart:io';\nimport 'dart:convert';\nimport '" + reader + "';\n" + r'''
String lines(String s) => s.split('\n').map((s) => s.trim()).join('\n').trim();
void main() {
  final file = File('lib/screens/alldebrid/alldebrid_files_screen.dart');
  final original = file.readAsStringSync();
  final frozen = jsonDecode(File('dev/tool/alldebrid_files_original_bodies.json').readAsStringSync()) as Map<String, dynamic>;
  for (final entry in frozen.entries) {
    if (lines(allDebridOriginalMember(entry.key)) != lines(entry.value as String)) throw StateError('Original declaration altered: ${entry.key}');
  }
  print('all 18 ORIGINAL declarations: PASS');
  final expected = allDebridOriginalMember('_AllDebridFilesScreenState._showLoading');
  if (!original.contains(expected)) throw StateError('Original body altered by normalization');
  final qualified = expected.replaceAll('_loadingDialogOpen', '_feedback.loadingDialogOpen').replaceAll('!mounted', '!_deps.mounted()').replaceAll('context: context', 'context: _deps.context()');
  if (qualified == expected) throw StateError('No fixture change');
  try {
    file.writeAsStringSync(original.replaceFirst(expected, qualified));
    if (lines(allDebridOriginalMember('_AllDebridFilesScreenState._showLoading')) != lines(expected)) throw StateError('Legitimate facade qualification not normalized');
    print('real facade qualified fields/live callbacks: PASS');
    file.writeAsStringSync(original.replaceFirst(expected, qualified.replaceAll('_feedback.loadingDialogOpen', '_navigation.loadingDialogOpen')));
    if (lines(allDebridOriginalMember('_AllDebridFilesScreenState._showLoading')) == lines(expected)) throw StateError('Foreign receiver masked');
    print('foreign receiver: rejected');
    file.writeAsStringSync(original.replaceFirst(expected, qualified.replaceAll('_deps.mounted()', 'savedMounted')));
    if (lines(allDebridOriginalMember('_AllDebridFilesScreenState._showLoading')) == lines(expected)) throw StateError('Cached mounted masked');
    print('cached mounted: rejected');
  } finally {
    file.writeAsStringSync(original);
  }
}
''')
        result = subprocess.run(['dart', str(probe)], cwd=fixture, capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr
        for line in result.stdout.splitlines():
            print('AllDebrid source reader ' + line)


def field_comments_self_test(config, sources, rows, lookup, complete):
    if not config.get('sidecars', {}).get('leading_field_comments'):
        return
    from check_settings_moves import sidecar, leading_line_comment_block
    for identity in sidecar('leading_field_comments', 'leading_field_comments', [], config=config):
        row=next(r for r in rows if r['original_name']==identity)
        key=(row['destination_file'],row['destination_class'],row['new_name'])
        node=lookup[key];block=leading_line_comment_block(sources[key[0]],node)
        assert block is not None
        at=sources[key[0]].rfind(block,0,node['start']);assert at>=0
        changed=dict(sources);changed[key[0]]=sources[key[0]][:at]+sources[key[0]][at+len(block):]
        # The same comment bytes survive; their ownership/placement changes.
        changed[key[0]]+=block
        errors=complete(changed)
        assert any('Leading field comment bytes or placement changed: '+identity in e for e in errors),(identity,errors)
        print('AllDebrid leading field comment '+identity+': misplaced bytes rejected independently')


def formatter_occurrence_self_test(package, config, sources, rows, original_nodes, lookup):
    """Real moved methods: exact braces never grant a scope exemption."""
    if not config.get('alldebrid_formatter_brace_occurrences'):
        return
    from check_verbatim_moves import parse
    from check_settings_moves import all_nodes, configured, sidecar
    from occurrence_field_bindings import failures
    import copy
    from alldebrid_files_formatter_braces import canonical_lookup
    source = config['source']
    with configured(config):
        assert not failures(original_nodes, lookup, rows, source, config, package=package)
        sites = sidecar('context_exceptions', 'sites', [], config=config)
    print('AllDebrid exact formatter occurrence positive: PASS')
    for site in sites:
        key = (site['file'], site['owner'], site['method'])
        node = lookup[key]
        body = 'Navigator.of(_deps.context(), rootNavigator: true).pop();' if site['method']=='dismissLoading' else '_f.fileSearchFocusNode.requestFocus();'
        for label, old, new in [
            ('predicate', 'if (_deps.mounted()) {', 'if (true) {'),
            ('body', body, body.replace('pop()', 'maybePop()').replace('requestFocus()', 'unfocus()')),
            ('prefix', 'if (_deps.mounted()) {', "debugPrint('unregistered prefix'); if (_deps.mounted()) {"),
            ('bare State callback', '_deps.mounted()', 'mounted'),
        ]:
            assert old in node['text'],(site,label)
            changed=dict(sources);changed[key[0]]=sources[key[0]][:node['start']]+node['text'].replace(old,new,1)+sources[key[0]][node['end']:]
            actual=all_nodes(parse(changed,package,occurrence_bindings=True))
            with configured(config):
                errors=failures(original_nodes,actual,rows,source,config,package=package)
            assert any('AllDebrid formatter occurrence evidence:' in e for e in errors),(site,label,errors)
            print('AllDebrid formatter '+site['method']+' '+label+': rejected independently')
    row=next(r for r in rows if r['original_name']=='_AllDebridFilesScreenState._focusFirstItem')
    key=(row['destination_file'],row['destination_class'],row['new_name']);node=lookup[key]
    old='_f.shouldFocusOnLoad = false;';assert old in node['text']
    changed=dict(sources);changed[key[0]]=sources[key[0]][:node['start']]+node['text'].replace(old,'{ '+old+' }',1)+sources[key[0]][node['end']:]
    actual=all_nodes(parse(changed,package,occurrence_bindings=True))
    with configured(config):errors=failures(original_nodes,actual,rows,source,config,package=package)
    assert any('Occurrence name/scope changed:' in e for e in errors),errors
    assert not any('AllDebrid formatter occurrence evidence:' in e for e in errors),errors
    print('AllDebrid unregistered scope block: rejected by unchanged occurrence alignment')
    bad=copy.deepcopy(config);bad['feature']='lib/features/foreign'
    try:
        canonical_lookup(lookup,rows,source,bad,package)
    except ValueError as error:
        assert 'outside AllDebrid' in str(error)
    else:
        raise AssertionError('AllDebrid formatter option escaped its feature key')
    print('AllDebrid formatter option on another feature: rejected independently')
    from unittest.mock import patch
    foreign = copy.deepcopy(sites[0]);foreign['file']='lib/features/foreign/formatter.dart'
    changed_rows=copy.deepcopy(rows)
    altered=next(r for r in changed_rows if r['destination_file']==sites[0]['file'] and r['new_name']==sites[0]['method'])
    altered['destination_file']=foreign['file']
    with patch('check_settings_moves.sidecar', return_value=[foreign]):
        try:
            canonical_lookup(lookup,changed_rows,source,config,package)
        except ValueError as error:
            assert 'Unregistered AllDebrid' in str(error)
        else:
            raise AssertionError('Formatter occurrence option accepted a foreign destination')
    print('AllDebrid formatter foreign destination: rejected independently')
    unregistered = copy.deepcopy(sites[0]);unregistered.update(file=config['feature']+'/presentation/legacy_alldebrid/alldebrid_navigation.dart',owner='AllDebridNavigation',method='focusFirstItem')
    with patch('check_settings_moves.sidecar', return_value=[unregistered]):
        try:
            canonical_lookup(lookup,rows,source,config,package)
        except ValueError as error:
            assert 'Unregistered AllDebrid' in str(error)
        else:
            raise AssertionError('Formatter occurrence option accepted an unregistered method')
    print('AllDebrid formatter unregistered method: rejected independently')


def source_reader_checkpoint_self_test(ROOT):
    """Read every frozen real declaration; exact formatter evidence stays strict."""
    import tempfile
    with tempfile.TemporaryDirectory(prefix='alldebrid-reader-checkpoint-', dir=ROOT / '.dart_tool') as directory:
        fixture = Path(directory)
        paths = [ROOT / 'lib/screens/alldebrid/alldebrid_files_screen.dart',
                 *sorted((ROOT / 'lib/features/alldebrid_files').rglob('*.dart'))]
        paths += [ROOT / 'dev/tool' / name for name in [
            'alldebrid_files_manifest.tsv', 'alldebrid_files_checker_config.json',
            'alldebrid_files_context_exceptions.json', 'alldebrid_files_original_bodies.json']]
        for path in paths:
            target = fixture / path.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(path.read_bytes())
        reader = (ROOT / 'test/support/alldebrid_files_source.dart').as_uri()
        probe = fixture / 'probe.dart'
        probe.write_text("import 'dart:io';\nimport 'dart:convert';\nimport '" + reader + "';\n" + r'''
String lines(String s) => s.split('\n').map((s) => s.trim()).join('\n').trim();
void main() {
  final frozen = jsonDecode(File('dev/tool/alldebrid_files_original_bodies.json').readAsStringSync()) as Map<String, dynamic>;
  for (final entry in frozen.entries) {
    if (lines(allDebridOriginalMember(entry.key)) != lines(entry.value as String)) {
      throw StateError('Frozen real declaration changed: ${entry.key}');
    }
  }
  print('all 18 frozen real declarations: PASS');
  final file = File('lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_feedback.dart');
  final before = file.readAsStringSync();
  const identity = '_AllDebridFilesScreenState._dismissLoading';
  void reject(String label, String old, String replacement) {
    if (old.allMatches(before).length != 1) throw StateError('Negative fixture is not exact: $label');
    file.writeAsStringSync(before.replaceFirst(old, replacement));
    var rejected = false;
    try {
      rejected = lines(allDebridOriginalMember(identity)) != lines(frozen[identity] as String);
    } on StateError {
      rejected = true;
    } finally {
      file.writeAsStringSync(before);
    }
    if (!rejected) throw StateError('Reader masked $label');
    print('$label: rejected independently');
  }
  reject('formatter edge comment', 'if (_deps.mounted()) {', 'if (_deps.mounted()) { /* unregistered edge */');
  reject('formatter predicate', 'if (_deps.mounted()) {', 'if (true) {');
  reject('formatter body', 'rootNavigator: true).pop()', 'rootNavigator: false).pop()');
  reject('formatter prefix', '_feedback.loadingDialogOpen = false;', '_feedback.loadingDialogOpen = true;');
  reject('formatter cached context', 'Navigator.of(_deps.context(),', 'Navigator.of(savedContext,');
  reject('formatter receiver swap', '_feedback.loadingDialogOpen = false;', '_navigation.loadingDialogOpen = false;');
}
''')
        result = subprocess.run(['dart', str(probe)], cwd=fixture, capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr
        for line in result.stdout.splitlines():
            print('AllDebrid checkpoint source reader ' + line)


def self_test(package):
    from check_verbatim_moves import ROOT, parse, original_leaves, split_names
    from check_settings_moves import all_nodes, check, configured, tokens, normalize
    from torbox_callback_identity import argument_ranges, check_callback_identities
    from occurrence_field_bindings import failures
    config = json.loads((ROOT / 'dev/tool/alldebrid_files_checker_config.json').read_text())
    assert config['occurrence_field_bindings']['mandatory_qualification'] is True, 'Explicit qualification pin required independently of the integrator default'
    rows = list(csv.DictReader((ROOT / 'dev/tool/alldebrid_files_manifest.tsv').open(), delimiter='\t'))
    source = config['source']
    original = subprocess.run(['git','show',config['baseline']+':'+source],cwd=ROOT,capture_output=True,text=True,check=True).stdout
    sources = {source:(ROOT/source).read_text()}
    sources.update({p.relative_to(ROOT).as_posix():p.read_text() for p in (ROOT/config['feature']).rglob('*.dart')})
    lookup = all_nodes(parse(sources,package,occurrence_bindings=True))
    original_nodes = original_leaves(parse({source:original},package,occurrence_bindings=True)[source]['declarations'],split_names(rows))
    def complete(changed):
        return check(original,changed,rows,source,package,context_guard=True,config=config)
    assert not complete(sources), 'real-config positive failed'
    assert not check_callback_identities(lookup,rows,source,config)
    print('AllDebrid real-config positive (no scaffold masking): PASS')
    field_comments_self_test(config, sources, rows, lookup, complete)
    def located(identity):
        row=next(r for r in rows if r['original_name']==identity)
        key=(row['destination_file'],row['destination_class'],row['new_name'])
        if key not in lookup:
            owner,_,name=identity.rpartition('.');key=(source,owner,name or identity)
        return key,lookup[key]
    def replaced(identity,before,after):
        key,node=located(identity);assert before in node['text'],(identity,before)
        changed=dict(sources);changed[key[0]]=sources[key[0]][:node['start']]+node['text'].replace(before,after,1)+sources[key[0]][node['end']:]
        return changed
    state='_AllDebridFilesScreenState'
    # Whole real declarations, no fixture-only substitute configuration.
    for name,before,after in [
        ('wrong builder State context','Theme.of(context)','Theme.of(otherContext)'),
        ('wrong add-dialog lexical context','Navigator.of(ctx).pop()', 'Navigator.of(context).pop()'),
        ('wrong refresh branch','await _loadLinks();','await _load();'),
    ]:
        member={'wrong builder State context':'_buildToolbar','wrong add-dialog lexical context':'_showAddMagnetDialog','wrong refresh branch':'_refresh'}[name]
        _, actual = located(state+'.'+member)
        if before not in actual['text']:
            before, after = {
                'wrong builder State context': ('Theme.of(_deps.context())', 'Theme.of(otherContext)'),
                'wrong refresh branch': ('await _deps.loadLinks();', 'await _deps.load();'),
            }[name]
        assert complete(replaced(state+'.'+member,before,after)),name
        print('AllDebrid '+name+': rejected')
    key,node=located(state+'.dispose')
    calls=list(re.finditer(r'[\w.]+\.dispose\(\);',node['text']))
    resources=[c for c in calls if c.group()!='super.dispose();'];assert len(resources)==10
    for label,(first,second) in [('first two',resources[:2]),('last two',resources[-2:])]:
        text=node['text'];mutant=text[:first.start()]+second.group()+text[first.end():second.start()]+first.group()+text[second.end():]
        changed=dict(sources);changed[key[0]]=sources[key[0]][:node['start']]+mutant+sources[key[0]][node['end']:]
        assert complete(changed)
        print('AllDebrid dispose order '+label+': rejected')
    changed=dict(sources);changed[key[0]]=sources[key[0]][:node['start']]+sources[key[0]][node['end']:]
    changed['fixture_moved_lifecycle.dart']='class MovedLifecycle { '+node['text']+' }'
    assert complete(changed);print('AllDebrid lifecycle moved out of State: rejected')
    key,node=located(state+'._loadingDialogOpen')
    changed=dict(sources);changed[config['feature']+'/fixture_duplicate.dart']='class Duplicate { '+node['text']+' }'
    assert complete(changed);print('AllDebrid duplicate field owner: rejected')
    accessor=lookup[(source,'','allDebridFilesTestAccess')]
    assert complete({**sources,source:sources[source][:accessor['start']]+sources[source][accessor['end']:]}), 'missing accessor'
    refresh = re.search(r"'refresh': (s[\w.]+)", accessor['text']).group(1)
    bad=accessor['text'].replace("'refresh': "+refresh, "'refresh': () => "+refresh+"()")
    assert bad!=accessor['text']
    assert complete({**sources,source:sources[source][:accessor['start']]+bad+sources[source][accessor['end']:]}), 'wrapped accessor'
    print('AllDebrid frozen accessor absent/wrapped: rejected')
    # Mutate each raw operand directly, bypassing the full token/scaffold rule:
    # assignment and comparison must independently reject BOTH negatives.
    for spec in config['callback_identities']:
        for site in spec['sites']:
            key,node=located(site['member']);values=tokens(node)
            if 'assignment_property' in site:
                i=values.index(site['assignment_property']);start=i+2;end=values.index(';',start)
            elif 'comparison_property' in site:
                i=values.index(site['comparison_property']);assert values[i+1]=='=='
                start=i+2;end=values.index(')',start)
            else:
                spans=argument_ranges(values,site['call']);start,end=spans[site.get('occurrence',0)][site['argument']]
            argument=values[start:end]
            leaf=argument[-2] if argument[-1:] == ['!'] else argument[-1]
            for label,replacement in [('wrapper',['(',')','=>',*argument,'(',')']),('same-class receiver swap',['secondInstance','.',leaf])]:
                mutant=copy.deepcopy(lookup);raw=list(values);raw[start:end]=replacement
                mutant[key]['tokens']=[{'text':t,'offset':i,'comment':False} for i,t in enumerate(raw)];mutant[key]['formatCommas']=[]
                errors=check_callback_identities(mutant,rows,source,config)
                assert any(spec['name'] in e for e in errors),(spec,site,label,errors)
                kind=site.get('call',site.get('assignment_property',site.get('comparison_property')))
                print('AllDebrid callback '+spec['name']+' '+site['member']+' '+kind+' '+label+': rejected independently')
    # A real _load declaration is placed in its registered destination, with
    # original AST-bound State references qualified through the pinned paths.
    # No generic mini-language or hand-built occurrence data substitutes for it.
    row=next(r for r in rows if r['original_name']==state+'._load')
    before=original_nodes[row['original_name']]
    moved=before['text'];by_leaf={r['original_name'].split('.')[-1]:r for r in rows}
    for o in sorted(before['occurrences'],key=lambda o:o['offset'],reverse=True):
        if o['kind']=='lexical' and o['binding']=='unbound' and o['name'] in by_leaf:
            target=by_leaf[o['name']]
            if target['destination_class'] in config['receiver_members']:
                path=('_deps' if not target['destination_class'].endswith('State') else next(p for p,v in config['receiver_paths'].items() if v==target['destination_class']))
                start=o['offset']-before['start'];end=o['end']-before['start']
                moved=moved[:start]+path+'.'+target['new_name']+moved[end:]
    moved=moved.replace('_load(', 'load(',1).replace('setState(', '_deps.setState(').replace('!mounted', '!_deps.mounted()')
    field=original_nodes[state+'._apiKey']['text'].replace('_apiKey','apiKey')
    binding_sources={source:original,row['destination_file']:'class '+row['destination_class']+' { '+moved+' }',
        config['feature']+'/presentation/legacy_alldebrid/alldebrid_library_state.dart':'class AllDebridLibraryState { '+field+' }'}
    def binding_errors(code):
        fixture=all_nodes(parse(code,package,occurrence_bindings=True))
        with configured(config):return failures(original_nodes,fixture,rows,source,config,members={row['original_name']},package=package)
    assert not binding_errors(binding_sources),binding_errors(binding_sources)
    print('AllDebrid real-config moved _load occurrence positive: PASS')
    for label,old,new,expected in [
        ('bare moved field','_library.loading','loading','Bare owner field reference:'),
        ('receiver swap','_library.loading','_navigation.loading','Occurrence alignment changed:'),
        ('qualified field replaces local','_library.apiKey = apiKey;','_library.apiKey = _library.apiKey;','lexical binding changed'),
        ('cached mounted callback','_deps.mounted()', 'savedMounted', 'name/scope changed'),
        ('wrong State setter','_deps.setState(', 'otherState.setState(', 'Occurrence alignment changed:'),
    ]:
        assert old in moved,(label,moved)
        changed={**binding_sources,row['destination_file']:binding_sources[row['destination_file']].replace(old,new,1)}
        errors=binding_errors(changed);assert any(expected in e for e in errors),(label,errors)
        print('AllDebrid occurrence '+label+': rejected independently')
    ledger=json.loads((ROOT/'dev/tool/alldebrid_files_playback_ledger.json').read_text())
    from torbox_callback_identity import arguments
    with configured(config):
        for site in ledger['sites']:
            _,node=located(site['member']);row=next(r for r in rows if r['original_name']==site['member'])
            current=tokens(node)
            for call,expected in [('VideoPlayerLaunchArgs',site['launch_arguments']),('PlaylistEntry',site['entry_arguments'])]:
                assert [[normalize(arg,rows,row) for arg in call_args] for call_args in arguments(current,call)] == [[normalize(arg,rows,row) for arg in expected]],site['member']+' '+call
            assert normalize(current,rows,row)==normalize(site['member_tokens'],rows,row),site['member']
    print('AllDebrid all three playback ledgers token-exact: PASS')
    source_reader_self_test(ROOT, original)
    source_reader_checkpoint_self_test(ROOT)
    formatter_occurrence_self_test(package, config, sources, rows, original_nodes, lookup)
