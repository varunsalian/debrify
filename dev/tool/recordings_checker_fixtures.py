"""ORIGINAL-derived syntax trees for the real recordings config and reader."""
import copy
import csv
import json
from collections import defaultdict

from check_verbatim_moves import ROOT, original_leaves, parse, split_names
from recordings_source_reader import original_source

STATE = '_RecordingsPageState'


def inputs(package):
    config = json.loads((ROOT / 'dev/tool/recordings_checker_config.json').read_text())
    rows = list(csv.DictReader((ROOT / 'dev/tool/recordings_manifest.tsv').open(), delimiter='\t'))
    original = original_source(config)
    leaves = original_leaves(parse({'<original>': original}, package,
                                   occurrence_bindings=True)['<original>']['declarations'], split_names(rows))
    return original, rows, config, leaves


def moved_body(row, node, rows, config, selected):
    by_old = {r['original_name'].split('.')[-1]: r for r in rows}
    aliases = {a['original_name']: a for a in config['planned_type_aliases']}
    moving = row['original_name'] in selected
    file = row['destination_file'] if moving else config['source']
    owner = row['destination_class'] if moving else node['owner']
    is_state = node['owner'] == STATE
    edits = {}
    for occurrence in node.get('occurrences', []):
        if occurrence['kind'] != 'lexical' or occurrence['binding'] != 'unbound':
            continue
        name = occurrence['name']; target = by_old.get(name); replacement = name
        if target and target['original_name'] in selected:
            if target['original_name'].startswith(STATE + '.'):
                target_owner = target['destination_class']
                if target_owner == owner:
                    replacement = target['new_name']
                else:
                    path = 'RecordingsHubData' if name == '_batteryNudgeDismissedPref' else next(p for p, c in config['receiver_paths'].items() if c == target_owner)
                    replacement = path + '.' + target['new_name']
            elif name in aliases:
                replacement = name if aliases[name]['file'] == file else aliases[name]['alias']
            else:
                replacement = target['new_name']
        elif is_state and moving:
            if name in ['context', 'mounted']: replacement = '_deps.' + name + '()'
            elif name == 'setState': replacement = '_deps.setState'
        if replacement != name:
            offset = occurrence['offset']; relative = offset - node['start']
            if '.' in replacement and node['text'][relative-1:relative] == '$':
                edits[offset-1] = (len(name)+1, '${' + replacement + '}')
            else: edits[offset] = (len(name), replacement)
    for token in node['tokens']:
        name = token['text']
        if token['comment']: continue
        alias = aliases.get(name)
        if alias and name in selected and alias['file'] != file:
            edits[token['offset']] = (len(name), alias['alias'])
    if moving and node['name'] != row['new_name']:
        token = next(t for t in node['tokens'] if not t['comment'] and t['text'] == node['name'])
        edits[token['offset']] = (len(node['name']), row['new_name'])
    text = node['text']
    for offset, (length, replacement) in sorted(edits.items(), reverse=True):
        relative = offset-node['start']; text = text[:relative]+replacement+text[relative+length:]
    if moving and row['original_name'] in config['forwarders']:
        text = text.replace('@override', '', 1)
    return text


def staged_config(base, rows, step, package):
    config = copy.deepcopy(base)
    config['completed_step'] = step
    config['_parser_package'] = str(package)
    active = {r['destination_file'] for r in rows if 0 < int(r['step']) <= step}
    config['type_aliases'] = [a for a in config['planned_type_aliases'] if a['file'] in active]
    config['file_aliases'] = config['type_aliases']
    config['additional_owners'] += [dict(file=a['file'], owner='', names=[a['alias']]) for a in config['type_aliases']]
    config['plain_sections'] = [s for s in config['planned_plain_sections'] if s['file'] in active]
    return config


def layout(original, rows, config, leaves, step):
    selected = {r['original_name'] for r in rows if 0 < int(r['step']) <= step}
    replacements = {}; destinations = defaultdict(list); comments = defaultdict(list)
    for leaf in config['comment_leaves']:
        if leaf['anchor'] in selected:
            replacements[leaf['offset']] = (leaf['end_offset'], '')
            comments[leaf['anchor']].append(leaf['text'])
    for row in rows:
        name = row['original_name']; node = leaves[name]
        if name in selected:
            replacements[node['start']] = (node['end'], config['forwarders'].get(name, {}).get('text', ''))
            body = '\n'.join(comments[name])+'\n'+moved_body(row, node, rows, config, selected)
            alias = next((a for a in config['type_aliases'] if a['original_name'] == name), None)
            if alias: body += '\ntypedef '+alias['alias']+' = '+alias['original_name']+';\n'
            destinations[row['destination_file'], row['destination_class']].append(body)
        elif node['owner'] == STATE:
            replacements[node['start']] = (node['end'], moved_body(row, node, rows, config, selected))
    facade = original
    for start, (end, body) in sorted(replacements.items(), reverse=True):
        facade = facade[:start]+body+facade[end:]
    data = json.loads((ROOT/config['sidecars']['scaffolding']).read_text())
    if step >= 2:
        marker = 'with WidgetsBindingObserver {'
        facade = facade.replace(marker, marker+'\n'+data['facade_text'], 1)
    sources = {config['source']: facade}
    for (path, owner), bodies in destinations.items():
        body = '\n'.join(bodies)
        header = data['section_text'].get(owner, '')
        sources[path] = sources.get(path, '') + (
            'class '+owner+' {\n'+header+'\n'+body+'\n}\n' if owner else body+'\n')
    if step >= 2:
        sources[data['dependencies_file']] = data['dependencies_text']
        sources[data['sections_file']] = data['composition_text'][str(min(step, 3))]
    return sources
