"""Real-manifest source layouts for the step-0 syntax/ownership guard proofs.

These deliberately contain no composition scaffolding. Compilation of the real
composition is a separate step-0b proof; these fixtures exercise the checker on
raw declaration moves without changing production files.
"""
import csv
import json
import io
import subprocess
from collections import defaultdict


def inputs(package, *, original_fixture=False):
    from check_verbatim_moves import ROOT, original_leaves, parse, split_names
    config = json.loads((ROOT/'dev/tool/debrify_tv_checker_config.json').read_text())
    rows = list(csv.DictReader((ROOT/'dev/tool/debrify_tv_manifest.tsv').open(), delimiter='\t'))
    if original_fixture:
        # ORIGINAL/raw-layout mutation fixtures use the reviewed planned map,
        # while the CLI's production check uses the live intermediate manifest.
        checkpoint = '58e3e599c5d5f29b0437b111cca1af9827cc3de1'
        def frozen(path):
            return subprocess.check_output(['git', 'show', checkpoint+':'+path], cwd=ROOT, text=True)
        config = json.loads(frozen('dev/tool/debrify_tv_checker_config.json'))
        rows = list(csv.DictReader(io.StringIO(frozen('dev/tool/debrify_tv_manifest.tsv')), delimiter='\t'))
        sidecar = ROOT/'.dart_tool/debrify_tv_parser/frozen_fixture_scaffolding.json'
        sidecar.parent.mkdir(parents=True, exist_ok=True)
        text = frozen('dev/tool/debrify_tv_scaffolding.json')
        if not sidecar.exists() or sidecar.read_text() != text:
            sidecar.write_text(text)
        config['sidecars']['scaffolding'] = str(sidecar)
    original = subprocess.check_output(['git','show',config['baseline']+':'+config['source']], cwd=ROOT, text=True)
    parsed = parse({'<original>': original}, package, occurrence_bindings=True)
    leaves = original_leaves(parsed['<original>']['declarations'], split_names(rows))
    return original, rows, config, leaves


def moved_body(row, node, rows, config, selected=None):
    """Apply only declaration renames, bound State receivers and live getters."""
    by_old = {r['original_name'].split('.')[-1]: r for r in rows}
    aliases = {a['original_name']: a['alias'] for a in config['planned_type_aliases']}
    edits = {}
    owner = node['owner']
    for occurrence in node.get('occurrences', []):
        name = occurrence['name']
        if occurrence['kind'] != 'lexical' or occurrence['binding'] != 'unbound':
            continue
        target = by_old.get(name)
        replacement = name
        if target and (selected is None or target['original_name'] in selected):
            if target['original_name'].rpartition('.')[0] == '_DebrifyTVScreenState':
                paths = [p for p, cls in config['receiver_owners'].items() if cls == target['destination_class']]
                paths = sorted(paths, key=lambda p: (not p.startswith(('_owners.', '_sections.')), len(p)))
                if target['destination_file'] != config['source'] and (selected is None or target['original_name'] in selected):
                    replacement = paths[0]+'.'+target['new_name']
            else:
                replacement = (name if name == node['name'] and name in aliases
                               else aliases.get(name, target['new_name']))
        elif owner == '_DebrifyTVScreenState' and row['destination_file'] != config['source'] and (selected is None or row['original_name'] in selected):
            if name in ['context','mounted']:
                replacement = '_deps.'+name+'()'
            elif name == 'setState':
                replacement = '_deps.setState'
        if replacement != name:
            offset = occurrence['offset']
            if '.' in replacement and node['text'][offset-node['start']-1:offset-node['start']] == '$':
                edits[offset-1] = (len(name)+1, '${'+replacement+'}')
            else:
                edits[offset] = (len(name), replacement)
    for token in node['tokens']:
        name = token['text']
        target = by_old.get(name)
        if (not token['comment'] and target and name.startswith('_') and name[1:2].isupper()
                and (selected is None or target['original_name'] in selected)):
            replacement = (name if name == node['name'] and name in aliases
                           else aliases.get(name, target['new_name']))
            if name != replacement:
                edits[token['offset']] = (len(name), replacement)
    old = row['original_name'].split('.')[-1]
    if old != row['new_name'] and (selected is None or row['original_name'] in selected):
        declaration = next(t for t in node['tokens'] if not t['comment'] and t['text']==old)
        edits[declaration['offset']] = (len(old), row['new_name'])
    text = node['text']
    for offset, (length, replacement) in sorted(edits.items(), reverse=True):
        relative = offset-node['start']
        assert 0 <= relative < len(text)
        text = text[:relative]+replacement+text[relative+length:]
    return text


def original_token(node, offset):
    return next(t['text'] for t in node['tokens'] if t['offset']==offset)


def layout(original, rows, config, leaves, selected=None):
    selected = set(selected if selected is not None else [r['original_name'] for r in rows if r['destination_file'] != config['source']])
    removals = {}
    destinations = defaultdict(list)
    for row in rows:
        name = row['original_name']
        if name not in selected or row['destination_file'] == config['source']:
            continue
        node = leaves[name]
        removals[node['start']] = node['end']
        destinations[(row['destination_file'], row['destination_class'])].append(moved_body(row, node, rows, config, selected))
    chip = {'_SpotlightChoiceChipState._focused', '_SpotlightChoiceChipState.build'}
    if chip <= selected:
        from check_verbatim_moves import parse
        # The wrapper itself is not a leaf, but travels with both members.
        start = original.index('class _SpotlightChoiceChipState ')
        end = leaves['_SpotlightChoiceChipState.build']['end']
        end = original.index('}', end)+1
        removals = {a:b for a,b in removals.items() if not start <= a < end}
        removals[start] = end
    facade = original
    replacements = {start: (end, '') for start, end in removals.items()}
    for row in rows:
        if row['original_name'] in selected and row['destination_file'] != config['source']:
            continue
        node = leaves[row['original_name']]
        if node['owner'] == '_DebrifyTVScreenState':
            replacements[node['start']] = (node['end'], moved_body(row, node, rows, config, selected))
    for start, (end, body) in sorted(replacements.items(), reverse=True):
        facade = facade[:start]+body+facade[end:]
    sources = {config['source']: facade}
    for (path, owner), bodies in destinations.items():
        body = '\n'.join(bodies)
        header = 'class '+owner+' {'
        if owner == '_SpotlightChoiceChipState':
            header = 'class _SpotlightChoiceChipState extends State<_SpotlightChoiceChip> {'
        sources[path] = sources.get(path, '') + (header+'\n'+body+'\n}\n' if owner else body+'\n')
    for alias in config.get('type_aliases', []):
        if alias['original_name'] in selected:
            sources[alias['file']] += 'typedef '+alias['alias']+' = '+alias['original_name']+';\n'
    return sources
