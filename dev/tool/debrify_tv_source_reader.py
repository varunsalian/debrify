#!/usr/bin/env python3
"""Resolve each manifest declaration, prove its current body, return raw ORIGINAL."""
import argparse
import csv
import hashlib
import json
import subprocess
from pathlib import Path

from check_settings_moves import all_nodes, check, configured
from check_verbatim_moves import ensure_parser_package, original_leaves, parse, split_names

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / 'dev/tool/debrify_tv_checker_config.json'
MANIFEST = ROOT / 'dev/tool/debrify_tv_manifest.tsv'


def original_source(config):
    result = subprocess.run(['git', 'show', config['baseline']+':'+config['source']], cwd=ROOT, text=True, capture_output=True)
    if result.returncode:
        raise ValueError('Missing ORIGINAL Git object '+config['baseline']+': '+result.stderr.strip())
    return result.stdout


def validate(original, sources, rows, config, package):
    with configured(config):
        parsed = parse({'<original>': original, **sources}, package, occurrence_bindings=True)
        lookup = all_nodes(parsed)
        declarations = original_leaves(parsed['<original>']['declarations'], split_names(rows))
        files = set()
        for row in rows:
            owner, _, name = row['original_name'].rpartition('.')
            retained = (config['source'], owner, name or row['original_name'])
            destination = (row['destination_file'], row['destination_class'], row['new_name'])
            present = {key for key in [retained, destination] if key in lookup}
            if len(present) != 1:
                raise ValueError(('Duplicate' if present else 'Missing')+' declaration ownership: '+row['original_name'])
            key = present.pop()
            if config.get('completed_step', 0) >= 8 and destination not in lookup:
                raise ValueError('Completed declaration remains in facade: '+row['original_name'])
            files.add(key[0])
        for path in sources:
            if path.startswith(config['feature']+'/') and path not in files and path not in config['scaffolds']:
                raise ValueError('Unregistered extra Debrify TV file: '+path)
        failures = check(original, sources, rows, config['source'], package, context_guard=True, config=config)
        if failures:
            raise ValueError('\n'.join(failures))
        # Existing native-settings expectation includes literal leading spaces.
        # Reverse only this registered callee/receiver after token/binding proof.
        identity = '_DebrifyTVScreenState._watch'
        row = next(r for r in rows if r['original_name'] == identity)
        owner, _, name = identity.rpartition('.')
        actual = lookup.get((row['destination_file'], row['destination_class'], row['new_name'])) or lookup[(config['source'], owner, name)]
        reference = declarations[identity]['text']
        marker = 'if (e is NativePlayerSettingsUnavailable) {'
        def block(text):
            lines = text.splitlines()
            positions = [i for i, line in enumerate(lines) if marker in line]
            if len(positions) != 1:
                raise ValueError('Native-settings physical block missing or duplicated')
            return lines[positions[0]:positions[0]+3]
        physical = block(actual['text'])
        target = next(r for r in rows if r['original_name'] == '_DebrifyTVScreenState._showNativeSettingsFailure')
        replacement = '_sections.feedback.'+target['new_name']+'(e);'
        physical = [line.replace(replacement, '_showNativeSettingsFailure(e);') for line in physical]
        if physical != block(reference):
            raise ValueError('Native-settings physical indentation/block changed')
    return sorted(files)


def read_current(complete=False):
    config = json.loads(CONFIG.read_text())
    if complete:
        config = {**config, 'completed_step':8}
    rows = list(csv.DictReader(MANIFEST.open(), delimiter='\t'))
    sources = {config['source']: (ROOT/config['source']).read_text()}
    sources.update({f.relative_to(ROOT).as_posix(): f.read_text() for f in (ROOT/config['feature']).rglob('*.dart')})
    original = original_source(config)
    inputs = {'original':original, 'sources':sources, 'config':config, 'rows':rows}
    digest = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode())
    for path in sorted((ROOT/'dev/tool').glob('*.py')):
        digest.update(path.name.encode()); digest.update(path.read_bytes())
    for path in [ROOT/'dev/tool/verbatim_ast.dart.txt', ROOT/'dev/tool/verbatim_parser.pubspec.lock']:
        digest.update(path.read_bytes())
    for path in config.get('sidecars', {}).values():
        digest.update((ROOT/path).read_bytes())
    cache = ROOT/'.dart_tool/debrify_tv_parser/source_reader_cache'
    cache.mkdir(parents=True, exist_ok=True)
    snapshot = cache/(digest.hexdigest()+'.json')
    if snapshot.exists():
        files = json.loads(snapshot.read_text())['files']
    else:
        package = ROOT/'.dart_tool/debrify_tv_parser/source_reader'
        package_config = package/'.dart_tool/package_config.json'
        ensure_parser_package(package, package_config)
        files = validate(original, sources, rows, config, package_config)
        snapshot.write_text(json.dumps({'files':files})+'\n')
    return {'files':files, 'source':original}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json', action='store_true')
    parser.add_argument('--complete', action='store_true')
    args = parser.parse_args()
    result = read_current(args.complete)
    print(json.dumps(result) if args.json else result['source'], end='' if not args.json else '\n')


if __name__ == '__main__':
    main()
