#!/usr/bin/env python3
"""Generate the frozen Phase-1 draft and a virtual analyzer/test probe only."""
import argparse
import copy
from collections import Counter
import json
from pathlib import Path
import re
import subprocess

from check_verbatim_moves import ROOT, parse
from check_settings_moves import tokens
from check_dart_moves import retained_manifest
from dart_move_history import git_text
from dart_move_partition import partition, frozen
from dart_move_fixture import materialize, render

SOURCE = 'lib/screens/video_player_screen.dart'
FEATURE = 'lib/features/video_player'
STATE = '_VideoPlayerScreenState'
MOVES = [
    ('_ManualSourceValidationFailure', 'models/vp_manual_source_validation_failure.dart', 'VpManualSourceValidationFailure'),
    ('_SeasonEpisodeSelection', 'models/vp_season_episode_selection.dart', 'VpSeasonEpisodeSelection'),
    ('_SubtitleApplyAttempt', 'models/vp_subtitle_apply_attempt.dart', 'VpSubtitleApplyAttempt'),
    ('_IptvZapPage', 'models/vp_iptv_zap_page.dart', 'VpIptvZapPage'),
    ('IptvCatchupRequestGate', 'models/iptv_catchup_request_gate.dart', 'IptvCatchupRequestGate'),
    ('_RandomChoiceTile', 'presentation/vp_random_choice_tile.dart', '_RandomChoiceTile'),
    (STATE + '._format', 'application/vp_format.dart', 'vpFormatDuration'),
    (STATE + '._pad2', 'application/vp_format.dart', 'vpPad2'),
    (STATE + '._generateFilenameHash', 'application/vp_filename_hash.dart', 'vpFilenameHash'),
    (STATE + '._normalisePosterUrl', 'application/vp_identity_text.dart', 'vpNormalisePosterUrl'),
    (STATE + '._normalisedContentType', 'application/vp_identity_text.dart', 'vpNormalisedContentType'),
    (STATE + '._identityMetaSubtitle', 'application/vp_identity_text.dart', 'vpIdentityMetaSubtitle'),
    (STATE + '._filterIdentitySearchResults', 'application/vp_identity_text.dart', 'vpFilterIdentitySearchResults'),
    (STATE + '._subtitleSearchDisplayLabel', 'application/vp_identity_text.dart', 'vpSubtitleSearchDisplayLabel'),
    (STATE + '._diagnosticSubtitleId', 'application/vp_subtitle_identity.dart', 'vpDiagnosticSubtitleId'),
    (STATE + '._subtitlePreferenceMatchesAttempt', 'application/vp_subtitle_identity.dart', 'vpSubtitlePreferenceMatchesAttempt'),
]
IMPORTS = {
    'models/vp_subtitle_apply_attempt.dart': ["import 'dart:async';", "import 'package:media_kit/media_kit.dart' as mk;"],
    'models/vp_iptv_zap_page.dart': ["import 'package:debrify/models/iptv_playlist.dart';"],
    'presentation/vp_random_choice_tile.dart': ["import 'package:flutter/material.dart';"],
    'application/vp_format.dart': ["import 'package:debrify/utils/time_formatters.dart';"],
    'application/vp_identity_text.dart': ["import 'package:debrify/models/stremio_addon.dart';"],
    'application/vp_subtitle_identity.dart': ["import 'package:media_kit/media_kit.dart' as mk;", "import '../models/vp_subtitle_apply_attempt.dart';"],
}


def draft(base, package):
    original = git_text(base, SOURCE)
    snapshot = retained_manifest(SOURCE, FEATURE, original, base, package)
    unit = parse({'base': original}, package, ownership=True)['base']
    spans, _, nodes = partition(unit, [STATE])
    spec = copy.deepcopy(snapshot)
    spec.update(status='draft', span_order=list(spans))
    spec['guards'] = {
        'occurrence_top_level_members': [key for key, _, _ in MOVES if key.startswith(STATE + '.')],
        'type_aliases': [{'original_name': '_RandomChoiceTile', 'alias': 'VpRandomChoiceTile'}],
    }
    targets = {key: (FEATURE + '/' + path, name) for key, path, name in MOVES}
    mapping = {key.split('.')[-1]: name for key, _, name in MOVES if key.split('.')[-1] != name}
    mapping['_RandomChoiceTile'] = 'VpRandomChoiceTile'
    for row in spec['declarations']:
        key = row['original']
        if key in targets:
            path, name = targets[key]
            row.update(fate='moved', destination=path, target=name)
            if key in {STATE + '._pad2', STATE + '._diagnosticSubtitleId', STATE + '._subtitlePreferenceMatchesAttempt'}:
                row['remove_static'] = True
        edits = []
        for old, new in mapping.items():
            if key == '_RandomChoiceTile' and old == '_RandomChoiceTile':
                continue
            count = tokens(spans[key]).count(old)
            if count:
                edits.append(dict(before=[old], after=[new], count=count))
        comments = Counter(t['text'] for t in spans[key]['tokens'] if t['comment'])
        for comment, count in comments.items():
            changed = re.sub(r'\b[A-Za-z_]\w*\b', lambda m: mapping.get(m[0], m[0]), comment)
            if changed != comment:
                edits.append(dict(before=[comment], after=[changed], count=count))
        if edits:
            row['substitutions'] = edits
    retained = {r['original'] for r in spec['declarations'] if r['fate'] != 'moved'}
    for owner, order in spec['facade_orders'].items():
        spec['facade_orders'][owner] = [k for k in order if k in retained or k + ':header' in retained]
    spec['span_order'] = [k for k in spans if k in retained]
    # New imports follow the existing exports. The gate export is adjacent to
    # the two compatibility exports; the exact reviewed directive list is frozen.
    imports = ["export '../features/video_player/models/iptv_catchup_request_gate.dart' show IptvCatchupRequestGate;"]
    imports += ["import '../features/video_player/" + path + "';" for path in dict.fromkeys(p for _, p, _ in MOVES)]
    prefix = parse({'imports': '\n'.join(imports)}, package, ownership=True)['imports']
    import_spans, _, _ = partition(prefix, [])
    old_count = len(unit['directives'])
    pinned = {}
    new_ids = []
    for index in range(len(imports)):
        key = '@directive:' + str(old_count + index)
        pinned[key] = tokens(import_spans['@directive:' + str(index)])
        new_ids.append(key)
    spec['scaffolding'][SOURCE] = pinned
    spec['facade_directives'] += prefix['directives']
    spec['facade_orders']['@directives'] += new_ids
    index = next(i for i, k in enumerate(spec['span_order']) if not k.startswith('@directive:'))
    spec['span_order'][index:index] = new_ids
    for path in dict.fromkeys(p for _, p, _ in MOVES):
        destination = FEATURE + '/' + path
        rows = sorted((r for r in spec['declarations'] if r.get('destination') == destination),
                      key=lambda r: spans[r['original']]['start'])
        # Parse a virtual destination solely to obtain reviewed AST structure.
        from dart_move_fixture import edited_text
        text = '\n'.join(IMPORTS.get(path, [])) + '\n'
        for row in rows:
            edits = row.get('substitutions', [])
            if row.get('remove_static'):
                edits = [dict(before=['static'], after=[], count=1), *edits]
            text += edited_text(original, spans[row['original']], edits)
        if path == 'presentation/vp_random_choice_tile.dart':
            text += '\ntypedef VpRandomChoiceTile = _RandomChoiceTile;\n'
        dest = parse({'dest': text}, package, ownership=True)['dest']
        physical, order, _ = partition(dest, [])
        scaffold = frozen(physical)
        for row in rows:
            del scaffold[row['target']]
        spec['destinations'][destination] = dict(directives=dest['directives'], orders=order,
                                               span_order=list(physical), split_containers=[])
        spec['scaffolding'][destination] = scaffold
    return original, snapshot, spec


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--probe', type=Path, required=True)
    args = parser.parse_args()
    common = Path(subprocess.check_output(
        ['git', '-C', str(ROOT), 'rev-parse', '--path-format=absolute', '--git-common-dir'], text=True).strip())
    evidence = common / 'refactor-evidence/vplayer/p1'
    if not args.probe.resolve().is_relative_to(evidence.resolve()):
        parser.error('--probe must be inside the Phase-1 evidence directory')
    original, snapshot, spec = draft(args.base, args.parser_package)
    directory = ROOT / 'dev/tool/dart_moves'
    directory.mkdir(exist_ok=True)
    for name, value in [('vplayer_p1_retained.json', snapshot), ('vplayer_p1.json', spec)]:
        (directory / name).write_text(json.dumps(value, indent=2) + '\n')
    for path, text in materialize(spec, original, args.parser_package).items():
        target = args.probe / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
    print('Drafted 16 moves into 10 destinations; application files untouched')


if __name__ == '__main__':
    main()
