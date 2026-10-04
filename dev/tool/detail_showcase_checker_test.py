"""Original and complete-split real-config fixtures, with staged alias proofs."""
import copy
import csv
import json
import subprocess
from pathlib import Path


def active_alias_config(config, layout, rows):
    config = copy.deepcopy(config)
    by_name = {r['original_name']: r for r in rows}
    owners = {}
    for name, alias in layout['aliases'].items():
        file = by_name[name]['destination_file']
        widget = name[1].isupper()
        constructors = ([{'name': 'showcase' + name[1:] + 'Constructor', 'target': 'new'}] if widget else [])
        if name == '_Circle':
            constructors.append({'name': 'showcaseCircleMarkConstructor', 'target': 'mark'})
        config['file_aliases'].append(dict(original_name=name, alias=alias, file=file, kind='widget' if widget else 'value', constructors=constructors))
        if widget:
            config['type_aliases'].append(dict(original_name=name, alias=alias, file=file))
            config['callback_call_aliases'][name] = alias
        owners.setdefault(file, []).extend([alias] + [c['name'] for c in constructors])
    config['additional_owners'] = [dict(file=f, owner='', names=n) for f, n in owners.items()]
    return config


def self_test(package=None):
    from check_settings_moves import ROOT, all_nodes, check
    from check_verbatim_moves import parse
    from detail_showcase_probe import split_sources
    from torbox_callback_identity import check_callback_identities
    config = json.loads((ROOT / 'dev/tool/detail_showcase_checker_config.json').read_text())
    fixtures = ROOT / 'dev/tool/detail_showcase_verbatim_fixtures'
    overlay = json.loads((fixtures / 'config.json').read_text())
    assert set(overlay) == {'source', 'feature'}
    config.update(overlay)
    rows = list(csv.DictReader((ROOT / 'dev/tool/detail_showcase_manifest.tsv').open(), delimiter='\t'))
    source = config['source']
    original = subprocess.check_output(['git', 'show', config['baseline'] + ':' + source], cwd=ROOT, text=True)
    current = {source: (ROOT / source).read_text()}
    current.update({str(p.relative_to(ROOT)): p.read_text() for p in (ROOT / config['feature']).rglob('*.dart')})
    assert not check(original, current, rows, source, package, config=config)
    print('Showcase real current configuration positive: PASS')
    ast = parse({'original': original}, package)['original']
    layout = json.loads((fixtures / 'layout.json').read_text())
    complete = split_sources(original, ast, layout)
    # Rebuild the fixed alias table rather than registering not-yet-created
    # aliases in the staged production config.
    virtual_config = copy.deepcopy(config)
    for key in ('type_aliases','file_aliases','additional_owners'):
        virtual_config[key] = []
    virtual_config['callback_call_aliases'] = {}
    virtual_config = active_alias_config(virtual_config, layout, rows)
    assert not check(original, complete, rows, source, package, config=virtual_config)
    print('Showcase real complete split and all alias pins positive: PASS')
    ahead = copy.deepcopy(virtual_config)
    assert check(original, {source: original}, rows, source, package, config=ahead), 'Alias registration ahead of owner accepted'
    print('Showcase ahead-of-owner alias registration: rejected')
    lookup = all_nodes(parse(complete, package))
    for case in json.loads((fixtures / 'cases.json').read_text()):
        row = next(r for r in rows if r['original_name'] == case['member'])
        path = row['destination_file']
        before = case['before']
        text = complete[path]
        assert before in text, 'No-op fixture: ' + case['name']
        changed = dict(complete)
        changed[path] = text.replace(before, case['after']) if case.get('all') else text.replace(before, case['after'], 1)
        assert changed[path] != text
        assert check(original, changed, rows, source, package, config=virtual_config), 'Accepted ' + case['name']
        print('Showcase real fixture ' + case['name'] + ': rejected')
    # Identity assertions are also exercised alone, so a token comparison
    # cannot hide a weak callback check.
    assert not check_callback_identities(lookup, rows, source, virtual_config)
    row = next(r for r in rows if r['original_name'] == 'ShowcaseIdentity')
    path = row['destination_file']
    for expr in ['m.onPrimary', 'secondModel.onTrailer', '() => m.onTrailer()']:
        changed = dict(complete)
        changed[path] = complete[path].replace('onTap: m.onTrailer,', 'onTap: ' + expr + ',', 1)
        assert check_callback_identities(all_nodes(parse(changed, package)), rows, source, virtual_config), expr
    print('Showcase callback-only identity/swapped-model/wrapper negatives: PASS')
