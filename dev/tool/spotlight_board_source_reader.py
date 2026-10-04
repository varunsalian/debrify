#!/usr/bin/env python3
"""Validate a manifest-owned body with AST tokens, then expose ORIGINAL text.

Comments and literals never pass through raw identifier replacement. Structural
normalization is shared with the move checker; lexical-context guards run on
physical tokens before normalization. Parser artifacts stay inside this worktree.
"""
import argparse
import csv
import difflib
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from check_settings_moves import (all_nodes, builder_context_signature, check_context, configured,
                                  declaration_tokens, remove_context_exceptions, sidecar,
                                  spotlight_formatter_commas)
from check_verbatim_moves import parse

ROOT = Path(__file__).resolve().parents[2]
SOURCE = 'lib/widgets/home/spotlight_board.dart'


def package_at(path):
    from check_verbatim_moves import parser_lock
    with parser_lock(path.parent.parent):
        return _package_at(path)


def _package_at(path):
    if not path.exists():
        directory = path.parent.parent
        directory.mkdir(parents=True, exist_ok=True)
        (directory / 'pubspec.yaml').write_text(
            "name: refactor_verbatim_parser\nenvironment:\n"
            "  sdk: '>=3.12.0 <4.0.0'\ndependencies:\n  analyzer: 14.3.0\n")
        shutil.copyfile(ROOT / 'dev/tool/verbatim_parser.pubspec.lock', directory / 'pubspec.lock')
        subprocess.run(['dart', 'pub', 'get', '--enforce-lockfile'], cwd=directory,
                       check=True, stdout=subprocess.DEVNULL)
    return path


def read_member(original_name, original, sources, rows, config, package):
    inputs = {'<original>': original, **sources}
    digest = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode())
    digest.update((ROOT / 'dev/tool/verbatim_ast.dart.txt').read_bytes())
    digest.update((ROOT / 'dev/tool/verbatim_parser.pubspec.lock').read_bytes())
    cache = ROOT / '.dart_tool/spotlight_board/source_reader_cache'
    cache.mkdir(parents=True, exist_ok=True)
    snapshot = cache / (digest.hexdigest() + '.json')
    if snapshot.exists():
        parsed = json.loads(snapshot.read_text())
    else:
        parsed = parse(inputs, package)
        with tempfile.NamedTemporaryFile(mode='w', dir=cache, delete=False) as output:
            json.dump(parsed, output)
        Path(output.name).replace(snapshot)
    lookup = all_nodes(parsed)
    row = next(r for r in rows if r['original_name'] == original_name)
    owner, _, name = original_name.rpartition('.')
    before = lookup[('<original>', owner, name)]
    key = (row['destination_file'], row['destination_class'], row['new_name'])
    actual = lookup.get(key)
    moved = actual is not None and row['destination_file'] != SOURCE
    if actual is None:
        actual = lookup.get((SOURCE, owner, name))
    if actual is None:
        raise ValueError('Manifest-owned body is missing: ' + original_name)
    if config.get('spotlight_state_field_bindings'):
        from spotlight_board_field_bindings import failures as field_binding_failures
        originals = {r['original_name']: lookup[('<original>', *r['original_name'].rsplit('.', 1))]
                     for r in rows if '.' in r['original_name']}
        failures = field_binding_failures(originals, lookup, [row] + [r for r in rows
                                          if r is not row], SOURCE, config, members=[original_name])
        if failures:
            raise ValueError('Owned field binding changed: ' + original_name + '\n' + '\n'.join(failures))
    receivers = config.get('bound_state_receivers', {}).get(original_name, [])
    if builder_context_signature(before, receivers) != builder_context_signature(actual, receivers):
        raise ValueError('Lexical/State context or mounted guard changed: ' + original_name)
    # Moving comments is verbatim, including ordinary prose. Do not let the
    # checker's documented private-symbol normalization hide a prose edit.
    def comments(node):
        return [re.sub(r'\s+', '', t['text']) for t in node['tokens']
                if t['text'].startswith(('//', '/*'))]
    if comments(before) != comments(actual):
        raise ValueError('Original comments changed: ' + original_name)
    with configured(config):
        actual = spotlight_formatter_commas(actual, row)
        sites = [s for s in sidecar('context_exceptions', 'sites', [], config=config)
                 if s['file'] == key[0] and s['owner'] == key[1] and s['method'] == key[2]]
        if sites:
            actual = remove_context_exceptions(actual, sites, rows, row)
        if 'context_guard' in row['allowed_edits'].split(','):
            failures = check_context(before, actual, rows, row)
            if failures:
                raise ValueError('Owned context guard changed: ' + original_name + '\n' + '\n'.join(failures))
        expected = declaration_tokens(before, rows, row, original=moved)
        observed = declaration_tokens(actual, rows, row)
    if expected != observed:
        difference = '\n'.join(difflib.unified_diff(expected, observed))
        raise ValueError('Non-verbatim manifest body: ' + original_name + '\n' + difference)
    return re.sub(r'\s+', '', before['text'])


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument('member')
    args.add_argument('--parser-package', type=Path, required=True)
    options = args.parse_args()
    config = json.loads((ROOT / 'dev/tool/spotlight_board_checker_config.json').read_text())
    rows = list(csv.DictReader((ROOT / 'dev/tool/spotlight_board_manifest.tsv').open(), delimiter='\t'))
    original = subprocess.check_output(['git', 'show', config['baseline'] + ':' + SOURCE],
                                       cwd=ROOT, text=True)
    sources = {SOURCE: (ROOT / SOURCE).read_text()}
    sources.update({str(p.relative_to(ROOT)): p.read_text()
                    for p in (ROOT / config['feature']).rglob('*.dart')})
    print(read_member(options.member, original, sources, rows, config,
                      package_at(options.parser_package.resolve())))


if __name__ == '__main__':
    main()
