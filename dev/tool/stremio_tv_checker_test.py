"""Real-config Stremio TV original/moved ownership and contract fixtures."""
import copy
import json
from pathlib import Path


def self_test(package, *, fixture_filter=None):
    import check_verbatim_moves as verbatim
    from check_settings_moves import check
    from stremio_tv_checker_fixtures import inputs, layout
    from stremio_tv_source_reader import validate
    original, rows, base, leaves = inputs(package)
    source = base['source']
    from collections import OrderedDict
    memo = OrderedDict()
    real_parse = verbatim.parse
    def cached(sources, package=None, *, occurrence_bindings=False):
        key = json.dumps([sources, occurrence_bindings], sort_keys=True)
        if key not in memo:
            memo[key] = real_parse(sources, package, occurrence_bindings=occurrence_bindings)
        result=memo[key]
        memo.move_to_end(key)
        while len(memo)>16: memo.popitem(last=False)
        return result
    verbatim.parse = cached
    import hashlib
    import stremio_tv_source_reader as reader
    real_check=check
    import check_settings_moves as engine
    real_normalize=engine.normalize
    normal_stamp=None
    normal_memo=OrderedDict()
    def cached_normalize(values,rows,row=None):
        key=(normal_stamp,tuple(values),json.dumps(row,sort_keys=True))
        if key not in normal_memo: normal_memo[key]=tuple(real_normalize(values,rows,row))
        result=normal_memo[key]
        normal_memo.move_to_end(key)
        while len(normal_memo)>2048: normal_memo.popitem(last=False)
        return list(result)
    engine.normalize=cached_normalize
    check_memo={}
    def cached_check(original,sources,rows,source,package,**kwargs):
        nonlocal normal_stamp
        normal_stamp=hashlib.sha256(json.dumps([rows,kwargs.get('config')],sort_keys=True).encode()).hexdigest()
        key=hashlib.sha256(json.dumps([original,sources,rows,source,kwargs],sort_keys=True).encode()).hexdigest()
        if key not in check_memo: check_memo[key]=real_check(original,sources,rows,source,package,**kwargs)
        return list(check_memo[key])
    check=cached_check
    real_reader_check=reader.check
    reader.check=cached_check
    counts = {'positive': 0, 'checker_negative': 0, 'reader_negative': 0}
    def run(sources, config=None):
        return check(original, sources, rows, source, package, context_guard=True, config=config or base)
    def positive(label, sources, config=None):
        config = config or base
        errors = run(sources, config)
        assert not errors, label+'\n'+'\n'.join(errors[:12])
        files = validate(original, sources, rows, config, package)
        assert files[0] == source
        counts['positive'] += 1
    def negative(label, sources, config=None):
        if fixture_filter and not any(part in label for part in fixture_filter): return
        config = config or base
        assert run(sources, config), 'checker accepted '+label
        try:
            validate(original, sources, rows, config, package)
        except (ValueError, KeyError):
            counts['reader_negative'] += 1
        else:
            raise AssertionError('reader accepted '+label)
        counts['checker_negative'] += 1
        print('Stremio TV fixture rejected: '+label)
    def changed(sources, before, after):
        result = dict(sources)
        owners = [p for p,s in result.items() if before in s]
        assert owners, before
        path = owners[0]; result[path] = result[path].replace(before, after, 1)
        return result
    def moved_config(selected):
        config = copy.deepcopy(base)
        files = {r['destination_file'] for r in rows if r['original_name'] in selected}
        config['type_aliases'] = [a for a in config['planned_type_aliases'] if a['file'] in files]
        config['plain_sections'] = [s for s in config['planned_plain_sections'] if s['file'] in files]
        records=set(config['occurrence_field_bindings']['record_paths'].values())
        if any(r['original_name'] in selected and r['destination_class'] in records for r in rows):
            # Step 2 activates these already-pinned composition declarations.
            # Simulated fixtures use an isolated sidecar, never edit the real one.
            import hashlib
            data=json.loads((verbatim.ROOT/config['sidecars']['scaffolding']).read_text())
            data['scaffolds'] += [dict(file=source,owner='_StremioTvScreenState',when_file_present=True,**spec) for spec in data['facade_composition']]
            path=verbatim.ROOT/'.dart_tool/stremio_tv_parser/fixture_sidecars'/ (hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()+'.json')
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_text(json.dumps(data)+'\n')
            config['sidecars']['scaffolding']=path.relative_to(verbatim.ROOT).as_posix()
        return config
    try:
        retained = {source: original}
        positive('ORIGINAL including annotated retained build (steps 0–5)', retained)
        # Excluded sibling multi-variable fields are never passed to the adapter.
        excluded = base['excluded_feature_files'][0]
        validate(original, {**retained, excluded: 'class Existing { int a=0,b=1; }'}, rows, base, package)
        counts['positive'] += 1
        scaffold_data = json.loads((verbatim.ROOT/base['sidecars']['scaffolding']).read_text())['scaffolds']
        templates = {}
        for spec in scaffold_data:
            if spec['owner'] == '' and spec['file'] in base['scaffolds']:
                templates[spec['file']] = ' '.join(spec['tokens'])
        positive('scaffold-only ownership', {**retained, **templates})
        selected = {r['original_name'] for r in rows if r['destination_file'] != source}
        config = moved_config(selected)
        moved = layout(original, rows, config, leaves, selected)
        positive('completed syntax layout with exact forwarder (step 6)', moved, config)
        complete = {**config, 'completed_step':7}
        positive('completed step 7 syntax ownership', {**moved,**templates}, complete)
        fields = {r['original_name'] for r in rows if leaves[r['original_name']]['variables'] and r['original_name'].startswith('_StremioTvScreenState.')}
        partial_members = fields | {
            '_StremioTvScreenState._openChannelFilter', '_StremioTvScreenState._pushChannelDetail',
            '_StremioTvScreenState._discoverAndLoad', '_StremioTvScreenState._refresh',
            '_StremioTvScreenState._sortedChannels', '_StremioTvScreenState._createSourceResolver',
        }
        partial_config = moved_config(partial_members)
        partial = layout(original, rows, partial_config, leaves, partial_members)
        positive('partial records hazards and two live widget sites', partial, partial_config)
        layout_members = selected
        layout_config = moved_config(layout_members)
        layout_only = layout(original, rows, layout_config, leaves, layout_members)
        positive('third live widget getter and leading annotation alignment', layout_only, layout_config)
        # A destination file can own some leaves while others remain in facade.
        one = fields | {'_StremioTvScreenState._providerShortLabel'}
        one_config = moved_config(one)
        positive('mixed owner file', layout(original, rows, one_config, leaves, one), one_config)
        negatives = [
            ('dispose order', '_contentRevision.dispose();\n    _searchBtnFocusNode.dispose();', '_searchBtnFocusNode.dispose();\n    _contentRevision.dispose();'),
            ('dispose drop', '_providerFocusNode.dispose();', ''),
            ('tab handler wrapper', '_tvContentFocusHandler!,\n      );', '() => _tvContentFocusHandler!(),\n      );'),
            ('watch hook clear', 'MainPageBridge.watchStremioTvChannel = null;', ''),
            ('search media servers', 'includeMediaServers: false,', 'includeMediaServers: true,'),
            ('play timeout', 'engineTimeout: const Duration(seconds: 10),', ''),
            ('generation check', '_playGeneration != myGeneration', 'false'),
            ('cancel bump', '_playGeneration++;\n        _notifyStartupAutoLaunchFailed', '_notifyStartupAutoLaunchFailed'),
            ('TorBox settle', 'Duration(seconds: 3)', 'Duration(seconds: 4)'),
            ('cleanup timeout', '.timeout(const Duration(seconds: 10))', '.timeout(const Duration(seconds: 11))'),
            ('detail poll', 'Duration(milliseconds: 120)', 'Duration(milliseconds: 121)'),
            ('detail cap', 'waitedMs < 8000', 'waitedMs < 8001'),
            ('resolver snapshot', 'final debridProvider = _debridProvider;', 'final debridProvider = "auto";'),
            ('comment bytes', 'Only clear if we\'re the active handler', 'Clear the active handler'),
            ('new const', 'Duration.zero,', 'const Duration(milliseconds: 0),'),
        ]
        for label,before,after in negatives:
            negative(label, changed(retained,before,after))
        # Every value and adjacent argument order is proved at both launch sites.
        from torbox_callback_identity import argument_ranges
        play = leaves['_StremioTvScreenState._playChannel']
        code = [t for t in play['tokens'] if not t['comment']]
        ranges = argument_ranges([t['text'] for t in code], 'VideoPlayerLaunchArgs')
        for site, args in enumerate(ranges, 1):
            assert len(args) == 19
            for ordinal, (a,b) in enumerate(args):
                name = code[a]['text']
                value_start = code[a+2]['offset']
                value_end = code[b-1]['offset']+len(code[b-1]['text'])
                bad = original[:value_start]+'null'+original[value_end:]
                negative(f'P{site} {name} value changed', {source:bad})
                begin = code[a]['offset']; end = code[b]['offset']+1
                negative(f'P{site} {name} dropped', {source:original[:begin]+original[end:]})
                if ordinal < len(args)-1:
                    c,d = args[ordinal+1]
                    first_end = code[b-1]['offset']+len(code[b-1]['text'])
                    second_begin = code[c]['offset']; second_end = code[d-1]['offset']+len(code[d-1]['text'])
                    bad = original[:begin]+original[second_begin:second_end]+original[first_end:second_begin]+original[begin:first_end]+original[second_end:]
                    negative(f'P{site} {name} reordered', {source:bad})
            first = code[args[0][0]]['offset']
            negative(f'P{site} extra launch argument', {source:original[:first]+'extraLauncherFlag: true, '+original[first:]})
        for label,before,after in [
            ('P1 overlay drop', "overlay.dismiss();\n        _notifyStartupAutoLaunchFailed('No auto-play stream resolved');", "_notifyStartupAutoLaunchFailed('No auto-play stream resolved');"),
            ('P2 overlay drop', 'overlay.setStage(PlayLoadStage.starting);\n      overlay.dismiss();', 'overlay.setStage(PlayLoadStage.starting);'),
            ('P1 notify drop', '            _notifyStartupPlayerLaunching();', ''),
            ('P2 notify drop', '      _notifyStartupPlayerLaunching();\n      _rememberPlaybackCursor', '      _rememberPlaybackCursor'),
            ('P1 cursor drop', '            _rememberPlaybackCursor(', '            unrelatedCursor('),
            ('P2 cursor drop', '      _rememberPlaybackCursor(\n        channel.id,', '      unrelatedCursor(\n        channel.id,'),
            ('Cancel bump after notify', "_playGeneration++;\n        _notifyStartupAutoLaunchFailed('Playback canceled');", "_notifyStartupAutoLaunchFailed('Playback canceled');\n        _playGeneration++;"),
            ('loadSettings gains setState', '_rotationMinutes = await StremioTvStorage.getStremioTvRotationMinutes();', 'setState(() => _rotationMinutes = 90);'),
            ('provider snapshot becomes live', '          debridProvider,', '          _debridProvider,'),
            ('manual callback wrapped', 'validateDirectUrl: _isValidStreamUrl,', 'validateDirectUrl: (url) => _isValidStreamUrl(url),'),
            ('provider callback swapped', 'stremioTvGuideDataProvider: _createGuideDataProvider(),', 'stremioTvGuideDataProvider: _createNextProvider(),'),
        ]:
            negative(label, changed(retained,before,after))
        for identity in ['_StremioTvScreenState._playChannel','_StremioTvScreenState._resolveChannelPlayback']:
            node = leaves[identity]; body = node['text']
            negative(identity+' media exclusion dropped', {source:original.replace(body,body.replace('includeMediaServers: false,','',1),1)})
            if identity.endswith('._playChannel'):
                negative(identity+' engine timeout changed', {source:original.replace(body,body.replace('engineTimeout: const Duration(seconds: 10),','engineTimeout: const Duration(seconds: 11),',1),1)})
            else:
                negative(identity+' engine timeout added', {source:original.replace(body,body.replace('includeMediaServers: false,','includeMediaServers: false, engineTimeout: const Duration(seconds: 10),',1),1)})
        for label,before,after in [
            ('per-access sections', 'late final StremioTvSections _sections =', 'StremioTvSections get _sections =>'),
            ('cached live widget getter', 'isTelevision : ( ) => widget . isTelevision', 'isTelevision : ( ) => false'),
            ('State context cached', 'context : ( ) => context', 'context : () => cachedContext'),
            ('State mounted cached', 'mounted : ( ) => mounted', 'mounted : () => true'),
        ]:
            negative(label, changed(moved,before,after),config)
        negative('per-build section', changed(moved,'_sections.layout.build(context);','StremioTvLayout(_deps).build(context);'),config)
        playback_path=next(r['destination_file'] for r in rows if r['original_name']=='_StremioTvScreenState._playGeneration')
        bad=dict(moved);bad[playback_path]=bad[playback_path].replace('class StremioTvPlaybackState {','class StremioTvPlaybackState { final cachedProvider = () {};',1)
        negative('provider factory cached in record field',bad,config)
        # Lexical contexts in nested builders stay at their exact occurrences.
        from check_verbatim_moves import parse
        units=parse(moved,package,occurrence_bindings=True)
        layout_path=next(r['destination_file'] for r in rows if r['original_name']=='_StremioTvScreenState.build')
        node=next(n for d in units[layout_path]['declarations'] for n in d['members'] if n['name']=='build')
        context=next(o for o in node['occurrences'] if o['name']=='context' and str(o.get('binding','')).startswith('decl:') and o['role']!='declaration')
        i=context['offset'];bad=dict(moved);bad[layout_path]=bad[layout_path][:i]+'_deps.context()'+bad[layout_path][i+7:]
        negative('lexical build context replaced by State callback',bad,config)
        chrome=next(r['destination_file'] for r in rows if r['original_name']=='_StremioTvScreenState._headerButton')
        bad=dict(moved);bad[chrome]=bad[chrome].replace('_deps.context()','context',1)
        negative('non-build State context replaced by bare lexical name',bad,config)
        bad=dict(moved);bad[layout_path]=bad[layout_path].replace('builder: (context, child)', 'builder: (otherContext, child)',1)
        negative('unused lexical builder context parameter renamed',bad,config)
        picker_path=next(r['destination_file'] for r in rows if r['original_name']=='_ManualSourcePickerSheetState')
        bad=dict(moved);bad[picker_path]=bad[picker_path].replace('setState(()','_deps.setState(()',1)
        negative('picker own setState qualified as screen State',bad,config)
        for label,before,after in [
            ('wrong widget receiver','_deps.isTelevision()','_owners.focus.isTelevision()'),
            ('cached widget getter','isTelevision: _deps.isTelevision(),','isTelevision: false,'),
            ('bare owner field','_owners.library.channels = _sections.library.sortedChannels(channels);','channels = _sections.library.sortedChannels(channels);'),
            ('lexical channels parameter','sortedChannels(List<StremioTvChannel> channels)','sortedChannels(List<StremioTvChannel> replaced)'),
            ('lexical builder context','app = AppThemeScope.of(context);','app = AppThemeScope.of(_deps.context());'),
        ]:
            sources = moved if before in '\n'.join(moved.values()) else partial
            cfg = config if sources is moved else partial_config
            negative(label,changed(sources,before,after),cfg)
        for identity in ['_StremioTvScreenState._openChannelFilter','_StremioTvScreenState._pushChannelDetail','_StremioTvScreenState.build']:
            path=next(r['destination_file'] for r in rows if r['original_name']==identity)
            for label,replacement in [('wrong receiver','_owners.focus.isTelevision()'),('cached snapshot','false'),('lost live call','_deps.isTelevision')]:
                bad=dict(moved);assert '_deps.isTelevision()' in bad[path]
                bad[path]=bad[path].replace('_deps.isTelevision()',replacement,1)
                negative(identity+' live getter '+label,bad,config)
        negative('P2 overlay/notify order',changed(retained,'overlay.dismiss();\n      _notifyStartupPlayerLaunching();','_notifyStartupPlayerLaunching();\n      overlay.dismiss();'))
        for indent in ['            ','      ']:
            start=original.index(indent+'_notifyStartupPlayerLaunching();')
            end=original.index(');',original.index(indent+'_rememberPlaybackCursor(',start))+2
            notify=indent+'_notifyStartupPlayerLaunching();'
            block=original[start:end]
            reordered=block.replace(notify+'\n','',1)+'\n'+notify
            negative('launch cursor/notify order '+str(len(indent)),{source:original[:start]+reordered+original[end:]})
        # The unchanged media-server regex's two predicates also reject each
        # simulated moved-source mutation independently of reader rejection.
        import re
        def media_predicates(sources):
            text='\n'.join(sources.values())
            matches=re.findall(r'searchByImdbWithStremio\([\s\S]*?\);',text)
            return len(matches)==2 and all('includeMediaServers: false' in m for m in matches)
        assert media_predicates(moved)
        resolve_path=next(r['destination_file'] for r in rows if r['original_name']=='_StremioTvScreenState._resolveChannelPlayback')
        call=re.search(r'searchByImdbWithStremio\([\s\S]*?\);',moved[resolve_path]).group(0)
        for label,before,after in [
            ('moved media exclusion true','includeMediaServers: false','includeMediaServers: true'),
            ('moved third media call',call,call+'\n await TorrentService.'+call),
            ('moved media call dropped','await TorrentService.'+call,'<String,dynamic>{};'),
        ]:
            bad=dict(moved);bad[resolve_path]=bad[resolve_path].replace(before,after,1)
            assert not media_predicates(bad),label
            negative(label,bad,config)
        forwarder = '@override Widget build(BuildContext context) => _sections.layout.build(context);'
        negative('forwarder changed',changed(moved,forwarder,forwarder.replace('context);','context,);')),config)
        negative('forwarder missing',changed(moved,forwarder,''),config)
        bad_config=copy.deepcopy(config)
        bad_config['forwarded_annotation_occurrences']['_SourcePickerItemState']=['override']
        controls=next(r['destination_file'] for r in rows if r['original_name']=='_SourcePickerItemState')
        bad=dict(moved);bad[controls]=bad[controls].replace('@override','',1)
        negative('annotation exception used for a different declaration',bad,bad_config)
        bad=dict(moved);bad[controls]=bad[controls].replace('@override','',1)
        negative('extra annotation removed outside forwarded build',bad,config)
        layout_path = next(r['destination_file'] for r in rows if r['original_name']=='_StremioTvScreenState.build')
        bad = dict(moved);bad[layout_path]=bad[layout_path].replace('Widget build(', '@override Widget build(',1)
        negative('moved build still annotated',bad,config)
        bad = dict(moved);bad[source]=original
        negative('duplicate original and moved body',bad,config)
        bad = dict(retained);bad[source]=bad[source].replace(leaves['_StremioTvScreenState._providerShortLabel']['text'],'',1)
        negative('missing ownership',bad)
        negative('extra non-scaffold file',{**retained,base['feature']+'/presentation/unregistered.dart':'class Unexpected {}'})
        bad = dict(moved);bad[layout_path]+='\nclass Extra {}\n'
        negative('mixed owner file extra declaration',bad,config)
        bad=dict(moved);bad[source]+='\n// Search\n'
        negative('free comment duplicated outside assigned owner',bad,config)
        negative('premature completion',retained,{**base,'completed_step':7})
        print('Stremio TV real-config self-tests: '+json.dumps(counts,sort_keys=True))
    finally:
        verbatim.parse = real_parse
        reader.check = real_reader_check
        engine.normalize = real_normalize
