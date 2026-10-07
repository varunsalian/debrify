"""Step-specific composition and physical callback envelopes for recordings."""
import json
from pathlib import Path

from check_verbatim_moves import ROOT, ensure_parser_package, parse
from check_settings_moves import all_nodes, tokens
from torbox_callback_identity import arguments, callback_argument


def code_tokens(node):
    # Shared AST marks optional formatter punctuation; positional record commas
    # remain semantic. Receiver/member/argument envelopes are otherwise exact.
    punctuation = set(node.get('formatCommas', []))
    return [t for t in node['tokens'] if not t['comment'] and t['offset'] not in punctuation]


def validate_sources(sources):
    return []


def validate_with_context(sources, config, rows):
    package = Path(config.get('_parser_package', ROOT / '.dart_tool/recordings_parser/contracts/.dart_tool/package_config.json'))
    ensure_parser_package(package.parent.parent, package)
    lookup = all_nodes(parse(sources, package, occurrence_bindings=True))
    source = config['source']; step = config['completed_step']; errors = []
    scaffolding = json.loads((ROOT / config['sidecars']['scaffolding']).read_text())
    by_old = {r['original_name']: r for r in rows}
    active = {r['destination_file'] for r in rows if 0 < int(r['step']) <= step}
    for row in rows:
        old = row['original_name']; owner, _, name = old.rpartition('.')
        retained = (source, owner, name or old)
        target = (row['destination_file'], row['destination_class'], row['new_name'])
        if target[0] == source or int(row['step']) > step:
            if retained not in lookup: errors.append('Future/retained row must stay in facade: '+old)
            if target != retained and target in lookup: errors.append('Destination ahead of step: '+old)
        else:
            if target not in lookup: errors.append('Activated destination missing: '+old)
            if old in config['forwarders']:
                if retained not in lookup: errors.append('Registered forwarder missing: '+old)
            elif retained in lookup: errors.append('Moved row remains in facade: '+old)
    aliases = [a for a in config['planned_type_aliases'] if a['file'] in active]
    if config['type_aliases'] != aliases or config['file_aliases'] != aliases:
        errors.append('Alias registration ahead of owner or differs from frozen step')
    for alias in config['type_aliases']:
        if alias['file'] not in sources: errors.append('Alias registration precedes physical owner: '+alias['alias'])
        declarations = sorted((node for (path, owner, _), node in lookup.items() if path == alias['file'] and not owner), key=lambda n: n['start'])
        position = next((i for i, node in enumerate(declarations) if node['name'] == alias['original_name']), -1)
        if position < 0 or position+1 >= len(declarations) or declarations[position+1]['name'] != alias['alias']:
            errors.append('Alias must immediately follow private owner: '+alias['alias'])
    sections = [s for s in config['planned_plain_sections'] if s['file'] in active]
    if config['plain_sections'] != sections:
        errors.append('Plain section registration differs from frozen step')
    required = active | {p for p, s in config['scaffold_file_steps'].items() if s <= step}
    for path in sorted(required-sources.keys()): errors.append('Activated file missing: '+path)
    allowed = {r['destination_file'] for r in rows} | set(config['scaffold_file_steps'])
    for path in sources:
        if path.startswith(config['feature']+'/') and path not in allowed:
            errors.append('Unregistered recordings file: '+path)
    for path, owner in config['plain_owner_files'].items():
        if path not in sources: continue
        node = lookup.get((path, '', owner)); code = tokens(node) if node else []
        if '{' not in code or code[:code.index('{')+1] != ['class', owner, '{']:
            errors.append('Section must be a plain bound owner: '+owner)
        expected = {'_deps', owner}
        if owner in ['RecordingsHubData', 'RecordingsHubLayout']: expected.add('_owners')
        if owner != 'RecordingsHubFormat': expected.add('_sections')
        registered = {r['new_name'] for r in rows if r['destination_class'] == owner}
        actual = {name for file, cls, name in lookup if file == path and cls == owner}-registered
        if actual != expected: errors.append('Section exact getter/constructor set changed: '+owner)
        for file, cls, name in lookup:
            if file != path or cls != owner: continue
            for occurrence in lookup[file, cls, name].get('occurrences', []):
                if occurrence['kind'] == 'lexical' and occurrence['binding'] == 'unbound' and occurrence['name'] in ['context', 'mounted', 'setState']:
                    errors.append('Bare State access in moved section: '+owner+'.'+name)
                if occurrence['kind'] == 'lexical' and occurrence['binding'] == 'unbound' and occurrence['name'] in {name.lstrip('_') for name in config['record_fields']['_RecordingsPageState']}:
                    errors.append('Bare recordings owner field in section: '+owner+'.'+name+' '+occurrence['name'])
    # Qualification belongs to the State workflow and its sections. A global
    # bare-name rule would incorrectly capture widget constructor labels and
    # public widget fields that happen to share an owners field spelling.
    workflow_owners = {'_RecordingsPageState', *config['plain_owner_files'].values()}
    moved_members = [r for r in rows if r['original_name'].startswith('_RecordingsPageState.')
                     and r['destination_class'] and 0 < int(r['step']) <= step]
    for (path, owner, name), node in lookup.items():
        if owner not in workflow_owners: continue
        for occurrence in node.get('occurrences', []):
            if occurrence['kind'] != 'lexical' or occurrence['binding'] != 'unbound': continue
            for row in moved_members:
                if owner != row['destination_class'] and occurrence['name'] in [row['original_name'].split('.')[-1], row['new_name']]:
                    errors.append('Moved workflow receiver missing: '+owner+'.'+name+' '+occurrence['name'])
    composition = lookup.get((scaffolding['sections_file'], '', 'RecordingsHubSections'))
    if step >= 2:
        if composition is None or tokens(composition) != scaffolding['composition_tokens'][str(min(step, 3))]:
            errors.append('Frozen step-'+str(min(step, 3))+' composition changed')
    elif composition is not None:
        errors.append('Composition precedes step 2')
    sites = json.loads((ROOT/config['sidecars']['callbacks']).read_text())['sites']
    for ordinal, spec in enumerate(sites):
        try:
            original = spec['member']; owner, _, name = original.rpartition('.')
            row = by_old.get(original)
            if row is None:
                row = by_old[owner]
                target = (row['destination_file'], row['new_name'], name)
            else:
                target = (row['destination_file'], row['destination_class'], row['new_name'])
            node = lookup.get(target) if 0 < int(row['step']) <= step else lookup.get((source, owner, name))
            if node is None: raise KeyError(original)
            frozen = spec['stages'][str(min(step, 3))]
            values = [t['text'] for t in code_tokens(node)]
            calls = arguments(values, frozen['call'])
            expression = callback_argument(calls[spec['occurrence']], spec)
            if len(calls) != spec['count'] or expression != frozen['expression']:
                errors.append('Physical callback/push envelope changed: '+str(ordinal)+' '+original+' '+str(spec['argument']))
        except (KeyError, IndexError, ValueError):
            errors.append('Missing physical callback/push envelope: '+str(ordinal)+' '+spec['member'])
    return errors
