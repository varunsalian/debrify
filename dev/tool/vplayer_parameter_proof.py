#!/usr/bin/env python3
"""Phase-1 parameter-only binding/import inventory using the shared analyzer AST."""
import argparse
import json
from pathlib import Path

from check_verbatim_moves import ROOT, parse, ensure_parser_package
from dart_move_history import load_manifest

# The already-compiling rename probe places these in top-level functions.
# This additional binding scan rejects State/service receivers in S itself.
ALLOWED_GLOBALS = {
    'Duration', 'String', 'int', 'bool', 'List', 'RegExp', 'StremioMeta',
    '_SubtitleApplyAttempt', 'mk', 'formatDuration',
}
ALLOWED_IMPORTS = {
    "import 'package:debrify/utils/time_formatters.dart';",
    "import 'package:debrify/models/stremio_addon.dart';",
    "import 'package:media_kit/media_kit.dart' as mk;",
    "import '../models/vp_subtitle_apply_attempt.dart';",
}


def inspect(node):
    tokens = [t['text'] for t in node['tokens'] if not t['comment']]
    errors = []
    if any(t in tokens for t in ('this', 'widget', 'context', 'super')):
        errors.append('State/UI receiver')
    globals_ = sorted({r['name'] for r in node['occurrences']
                       if r['kind'] == 'lexical' and r['binding'] == 'unbound'})
    unexpected = set(globals_) - ALLOWED_GLOBALS
    if unexpected:
        errors.append('non-parameter reference: ' + ', '.join(sorted(unexpected)))
    return globals_, errors


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--parser-package', type=Path, required=True)
    cli.add_argument('--output', type=Path, required=True)
    args = cli.parse_args()
    package = args.parser_package.resolve()
    if not package.is_relative_to(ROOT / '.dart_tool/vplayer_parser'):
        cli.error('isolated .dart_tool/vplayer_parser package required')
    ensure_parser_package(package.parents[1], package)
    draft = load_manifest(ROOT / 'dev/tool/dart_moves/vplayer_p1.json')
    source = (ROOT / draft['source']).read_text()
    unit = parse({draft['source']: source}, package, occurrence_bindings=True, ownership=True)[draft['source']]
    state = next(d for d in unit['declarations'] if d['name'] == '_VideoPlayerScreenState')
    rows = []
    for row in draft['declarations']:
        if row['fate'] != 'moved' or not row['original'].startswith('_VideoPlayerScreenState.'):
            continue
        name = row['original'].split('.')[1]
        node = next(m for m in state['members'] if m['name'] == name)
        globals_, errors = inspect(node)
        rows.append(dict(declaration=row['original'], globals=globals_, errors=errors,
                         occurrences=node['occurrences'], allowed_imports=sorted(ALLOWED_IMPORTS)))
    imports = {path: spec['directives'] for path, spec in draft['destinations'].items() if '/application/' in path}
    if any(set(values) - ALLOWED_IMPORTS for values in imports.values()):
        raise SystemExit('unexpected application imports')
    report = dict(application_imports=imports, checkpoint='80839d827383b05078178f292b56efbddd166fb1', helpers=rows,
        proof='Shared analyzer lexical binding scan at S, plus compiling top-level strict-feature rename probe at R (unchanged helper bodies at S). No State field/member, service, I/O or UI dependency.',
        compiling_probe='probe-at-R-analyze.txt')
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    errors = [r for r in rows if r['errors']]
    if errors:
        raise SystemExit(json.dumps(errors))
    print(f'PASS: {len(rows)} parameter-only helpers; no State/service/I/O references')


if __name__ == '__main__':
    main()
