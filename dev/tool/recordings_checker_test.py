"""Real-config recordings ORIGINAL, partial, completed and rejection fixtures."""
import argparse
import copy
import json
import hashlib
import functools
from collections import OrderedDict
from pathlib import Path

from check_settings_moves import check
from check_verbatim_moves import ensure_parser_package
from recordings_checker_fixtures import inputs, layout, staged_config
from recordings_source_reader import validate


def fixture_parser_cache(function):
    @functools.wraps(function)
    def wrapped(*args, **kwargs):
        import check_verbatim_moves as parser
        import recordings_contracts as contracts
        import stremio_tv_source_reader as reader
        import check_settings_moves as engine
        original = parser.parse
        original_normalize, original_configure = engine.normalize, engine.configure
        previous = (contracts.parse, reader.parse)
        memo = OrderedDict()
        fragments = OrderedDict()
        normal_memo = OrderedDict()
        stamp = json.dumps(engine.CONFIG, sort_keys=True)
        def configure(config):
            nonlocal stamp
            original_configure(config)
            stamp = json.dumps(config, sort_keys=True)
        def normalize(values, rows, row=None):
            names = tuple((r['original_name'], r['new_name']) for r in rows)
            key = (stamp, tuple(values), names, json.dumps(row, sort_keys=True))
            if key not in normal_memo: normal_memo[key] = tuple(original_normalize(values, rows, row))
            result = normal_memo[key]; normal_memo.move_to_end(key)
            while len(normal_memo) > 2048: normal_memo.popitem(last=False)
            return list(result)
        def cached(sources, package=None, *, occurrence_bindings=False):
            key = hashlib.sha256(json.dumps([sources, str(package), occurrence_bindings], sort_keys=True).encode()).hexdigest()
            # Scaffolds/forwarders repeat between every full source variant.
            # Keep their small ASTs separately so they cannot evict the trees.
            cache, limit = (fragments, 128) if sum(map(len, sources.values())) < 25000 else (memo, 8)
            if key not in cache: cache[key] = original(sources, package, occurrence_bindings=occurrence_bindings)
            result = cache[key]; cache.move_to_end(key)
            while len(cache) > limit: cache.popitem(last=False)
            return result
        parser.parse = contracts.parse = reader.parse = cached
        engine.normalize, engine.configure = normalize, configure
        try: return function(*args, **kwargs)
        finally:
            parser.parse = original
            contracts.parse, reader.parse = previous
            engine.normalize, engine.configure = original_normalize, original_configure
    return wrapped


@fixture_parser_cache
def self_test(package, *, reader_only=False):
    import check_settings_moves as engine
    probe = [{'original_name': 'Owner._recordings_cache_probe', 'new_name': 'first'}]
    assert engine.normalize(['_recordings_cache_probe'], probe) == ['first']
    probe[0]['new_name'] = 'second'
    assert engine.normalize(['_recordings_cache_probe'], probe) == ['second']
    original, rows, base, leaves = inputs(package)
    source = base['source']; reports = []; positives = 0
    stages = {}

    def positive(label, sources, config):
        nonlocal positives
        try:
            errors = check(original, sources, rows, source, package, context_guard=True, config=config)
        except ValueError as error:
            errors = ['AST declaration identity rejected: '+str(error)]
        assert not errors, label+'\n'+'\n'.join(errors[:20])
        assert validate(original, sources, rows, config, package)[0] == source
        positives += 1

    def negative(label, sources, config):
        try:
            errors = check(original, sources, rows, source, package, context_guard=True, config=config)
        except ValueError as error:
            errors = ['AST declaration identity rejected: '+str(error)]
        assert errors, 'checker accepted '+label
        try:
            validate(original, sources, rows, config, package)
        except (ValueError, KeyError) as error:
            rejection = str(error)
        else:
            raise AssertionError('reader accepted '+label)
        reports.append(dict(label=label, checker_guards=errors, reader_rejection=rejection))
        print('Recordings fixture rejected: '+label)

    def changed(sources, before, after, *, path=None):
        result = dict(sources)
        found = [p for p, text in result.items() if before in text and (path is None or path == p)]
        assert found, 'Fixture pattern missing: '+before
        result[found[0]] = result[found[0]].replace(before, after, 1)
        return result

    for step in range(5):
        config = staged_config(base, rows, step, package)
        sources = layout(original, rows, config, leaves, step)
        positive('step '+str(step), sources, config)
        stages[step] = (sources, config)
    scaffolding = json.loads((Path(__file__).resolve().parent.parent.parent/base['sidecars']['scaffolding']).read_text())
    retained, zero = stages[0]
    positive('scaffold-only dependencies preserve ORIGINAL ownership', {**retained, scaffolding['dependencies_file']: scaffolding['dependencies_text']}, zero)
    for label, before, after in [
        ('reworded comment', 'never a whole-page', 'never an entire-page'),
        ('dispose order', '_now.dispose();\n    _firstLibraryFocus.dispose();', '_firstLibraryFocus.dispose();\n    _now.dispose();'),
        ('debug label', 'recordings_first_library_row', 'recordings_other_row'),
        ('ticker duration', 'Duration(seconds: 1)', 'Duration(seconds: 2)'),
    ]:
        negative(label, changed(retained, before, after), zero)
    one, one_config = stages[1]
    renamed = dict(one)
    hub_path = next(a['file'] for a in base['planned_type_aliases'] if a['original_name'] == '_HubBar')
    renamed[hub_path] = renamed[hub_path].replace('_HubBar', '_RenamedHubBar')
    negative('renamed private widget', renamed, one_config)
    negative('alias used in owner file', changed(one, 'State<_HubButton>', 'State<RecordingsHubHubButton>', path=next(a['file'] for a in base['planned_type_aliases'] if a['original_name']=='_HubButton')), one_config)
    negative('alias target changed', changed(one, 'typedef RecordingsHubHubBar = _HubBar;', 'typedef RecordingsHubHubBar = _EmptyHint;'), one_config)
    ahead = copy.deepcopy(zero); ahead['type_aliases'] = base['planned_type_aliases'][:1]; ahead['file_aliases'] = ahead['type_aliases']
    negative('registration ahead of physical owner', retained, ahead)
    duplicate = {**one, source: one[source]+'\n'+leaves['_HubBar']['text']}
    negative('mixed duplicate declaration ownership', duplicate, one_config)
    two, two_config = stages[2]; three, three_config = stages[3]
    negative('step 2 tree under step 3 specification', two, three_config)
    negative('step 3 tree under step 2 specification', three, two_config)
    negative('bare owner assignment', changed(two, '_owners.live = live;', 'live = live;'), two_config)
    negative('bare facade owner read', changed(two, '_owners.library.isEmpty', '_library.isEmpty', path=source), two_config)
    negative('bare facade moved method', changed(two, '_sections.data.loadAll()', 'loadAll()', path=source), two_config)
    negative('local now captured by owners', changed(two, '_owners.batteryNudgeDismissedAtMs = now', '_owners.batteryNudgeDismissedAtMs = _owners.now'), two_config)
    negative('receiver swapped between sections', changed(three, '_sections.data.loadAll()', '_sections.format.loadAll()'), three_config)
    negative('context cached instead of live getter', changed(three, '_deps.context()', 'cachedContext'), three_config)
    negative('lexical build context replaced', changed(three, 'Navigator.of(context).maybePop()', 'Navigator.of(_deps.context()).maybePop()'), three_config)
    negative('mounted getter hoisted', changed(three, 'if (!_deps.mounted()) return;', 'final cachedMounted = _deps.mounted(); if (!cachedMounted) return;'), three_config)
    for label, before, after in [
        ('lazy owners', 'final _owners = RecordingsHubOwners();', 'RecordingsHubOwners? _cachedOwners; RecordingsHubOwners get _owners => _cachedOwners ??= RecordingsHubOwners();'),
        ('cached State context', 'context: () => context', 'context: context'),
        ('cached mounted', 'mounted: () => mounted', 'mounted: mounted'),
        ('wrapped setState', 'setState: setState', 'setState: (fn) => setState(fn)'),
        ('sections reconstructed every access', '_composition ??=', ''),
    ]:
        negative(label, changed(three, before, after), three_config)
    negative('wrong section class wired', changed(three, 'data = RecordingsHubData(deps)', 'data = RecordingsHubFormat(deps)'), three_config)
    negative('section constructor reads deps', changed(three, 'RecordingsHubActions(this._deps);', 'RecordingsHubActions(this._deps) { _deps.context(); }'), three_config)
    negative('section constructor creates resource', changed(three, 'RecordingsHubData(this._deps);', 'RecordingsHubData(this._deps) { Timer(Duration.zero, () {}); }'), three_config)
    negative('unused section getter', changed(three, 'class RecordingsHubFormat {', 'class RecordingsHubFormat { RecordingsHubOwners get _owners => _deps.owners;'), three_config)
    forwarder = base['forwarders']['_RecordingsPageState.build']['text']
    for label, replacement in [
        ('missing build forwarder', ''),
        ('altered forwarder extra statement', '@override Widget build(BuildContext context) { print(context); return _sections.layout.build(context); }'),
        ('altered forwarder receiver', forwarder.replace('_sections.layout', '_sections.actions')),
        ('full facade and moved build duplicate', leaves['_RecordingsPageState.build']['text']),
        ('cached forwarder section', forwarder.replace('_sections.layout', '_cachedLayout')),
    ]:
        negative(label, changed(three, forwarder, replacement, path=source), three_config)
    negative('moved build still annotated', changed(three, 'Widget build(BuildContext context)', '@override Widget build(BuildContext context)', path=base['feature']+'/presentation/legacy_recordings/recordings_hub_layout.dart'), three_config)
    # Exercise every frozen callback envelope independently, before canonicalization.
    sites = json.loads((Path(__file__).resolve().parent.parent.parent/base['sidecars']['callbacks']).read_text())['sites']
    from check_verbatim_moves import parse
    from check_settings_moves import all_nodes, configured
    from torbox_callback_identity import argument_ranges
    with configured(three_config): lookup = all_nodes(parse(three, package, occurrence_bindings=True))
    by_old = {row['original_name']: row for row in rows}
    for ordinal, spec in enumerate(sites):
        old = spec['member']; owner, _, name = old.rpartition('.')
        row = by_old.get(old) or by_old[owner]
        key = (row['destination_file'], row['destination_class'], row['new_name']) if old in by_old else (row['destination_file'], row['new_name'], name)
        node = lookup[key]; code = [t for t in node['tokens'] if not t['comment']]
        ranges = argument_ranges([t['text'] for t in code], spec['stages']['3']['call'])[spec['occurrence']]
        if isinstance(spec['argument'], int): a, b = ranges[spec['argument']]
        else:
            a, b = next((a+2,b) for a,b in ranges if [t['text'] for t in code[a:a+2]] == [spec['argument'], ':'])
        start = code[a]['offset']; end = code[b-1]['offset']+len(code[b-1]['text'])
        mutant = dict(three); mutant[key[0]] = mutant[key[0]][:start]+'null'+mutant[key[0]][end:]
        negative('callback/push envelope '+str(ordinal)+' '+old+' '+str(spec['argument']), mutant, three_config)
    for label, before, after in [
        ('compile-valid unawaited wrapper dropped', '() => unawaited(_sections.actions.play(entry))', '() => _sections.actions.play(entry)'),
        ('desktop Stop inner member swapped', '_sections.actions.stopDesktop(capture)', '_sections.actions.stopAndroid(capture)'),
        ('capture bytes cached', '() => capture.bytes', '() => cachedBytes'),
        ('preset pop lexical d changed', 'pop(d)', 'pop(true)'),
        ('schedule DOWN guard term removed', '_owners.schedules.isEmpty &&', ''),
        ('timer block owner receiver swapped', '_owners.now.value = DateTime.now()', '_sections.format.now.value = DateTime.now()'),
        ('Builder display receiver swapped', '_sections.format.displayFor(entry)', '_sections.data.displayFor(entry)'),
        ('DevicePreferences then owner swapped', '_owners.batteryNudgeDismissedAtMs = at', '_sections.data.batteryNudgeDismissedAtMs = at'),
        ('key handler callback swapped', 'widget.onCancel();', 'widget.onPlay();'),
    ]:
        negative(label, changed(three, before, after), three_config)
    print('Recordings fixtures: '+str(positives)+' positives; '+str(len(reports))+' checker and '+str(len(reports))+' reader rejections')
    return dict(positive=positives, checker_negative=len(reports), reader_negative=len(reports), reports=reports)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--parser-package', type=Path, required=True)
    p.add_argument('--report', type=Path)
    args = p.parse_args(); ensure_parser_package(args.parser_package.parent.parent, args.parser_package)
    result = self_test(args.parser_package)
    if args.report: args.report.write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__': main()
