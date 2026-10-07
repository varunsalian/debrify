#!/usr/bin/env python3
"""Manifest-owned AST source proof, sharing the integrated ownership reader."""
import argparse
import csv
import hashlib
import json
import subprocess
from pathlib import Path

from check_verbatim_moves import ensure_parser_package
from stremio_tv_source_reader import validate as ownership_validate

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / 'dev/tool/recordings_checker_config.json'
MANIFEST = ROOT / 'dev/tool/recordings_manifest.tsv'


def original_source(config):
    raw = subprocess.check_output(
        ['git', 'show', config['baseline'] + ':' + config['source']], cwd=ROOT)
    if hashlib.sha256(raw).hexdigest() != config['original_sha256']:
        raise ValueError('ORIGINAL recordings hash differs')
    return raw.decode()


def select_sources(config):
    return {config['source']: (ROOT / config['source']).read_text(), **{
        p.relative_to(ROOT).as_posix(): p.read_text()
        for p in sorted((ROOT / config['feature']).rglob('*.dart'))}}


def validate(original, sources, rows, config, package):
    config = {**config, '_parser_package': str(package)}
    return ownership_validate(original, sources, rows, config, package)


def read_current(complete=False, package=None):
    config = json.loads(CONFIG.read_text())
    if complete:
        config = {**config, 'completed_step': config['completion_step']}
    rows = list(csv.DictReader(MANIFEST.open(), delimiter='\t'))
    original = original_source(config)
    sources = select_sources(config)
    digest = hashlib.sha256(json.dumps(
        [original, sources, rows, config], sort_keys=True).encode())
    for p in sorted((ROOT / 'dev/tool').glob('*.py')):
        digest.update(p.name.encode())
        digest.update(p.read_bytes())
    for p in [ROOT / 'dev/tool/verbatim_ast.dart.txt',
              ROOT / 'dev/tool/verbatim_parser.pubspec.lock',
              *[ROOT / p for p in config['sidecars'].values()]]:
        digest.update(p.read_bytes())
    directory = ROOT / '.dart_tool/recordings_parser/source_reader'
    pc = package or directory / '.dart_tool/package_config.json'
    ensure_parser_package(pc.parent.parent, pc)
    cache = directory / 'cache'
    cache.mkdir(parents=True, exist_ok=True)
    snapshot = cache / (digest.hexdigest() + '.json')
    if snapshot.exists():
        files = json.loads(snapshot.read_text())['files']
    else:
        files = validate(original, sources, rows, config, pc)
        snapshot.write_text(json.dumps({'files': files}) + '\n')
    return dict(files=files, source=original,
                current_source='\n'.join(sources[p] for p in files))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--json', action='store_true')
    p.add_argument('--complete', action='store_true')
    p.add_argument('--parser-package', type=Path)
    p.add_argument('--self-test', action='store_true')
    args = p.parse_args()
    if args.self_test:
        from recordings_checker_test import self_test
        pc = args.parser_package or ROOT / '.dart_tool/recordings_parser/reader_test/.dart_tool/package_config.json'
        ensure_parser_package(pc.parent.parent, pc)
        self_test(pc, reader_only=True)
        return
    result = read_current(args.complete, args.parser_package)
    print(json.dumps(result) if args.json else result['source'],
          end='\n' if args.json else '')


if __name__ == '__main__':
    main()
