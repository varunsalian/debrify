#!/usr/bin/env python3
"""Panel-specific mandatory-token proof of optional formatter comma changes."""
import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

SOURCE = 'lib/widgets/episodes_panel.dart'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--original', required=True)
    parser.add_argument('--formatted', type=Path, required=True)
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path.cwd()
    adapter = root / 'dev/tool/merged_detail_format_proof.dart.txt'
    kernel = args.parser_package.parent / 'episodes_panel_format_proof.dill'
    subprocess.run(['dart', 'compile', 'kernel',
                    '--packages=' + str(args.parser_package), '-o', str(kernel),
                    str(adapter)], check=True, stdout=subprocess.DEVNULL)
    original = subprocess.check_output(
        ['git', 'show', args.original + ':' + SOURCE], text=True)
    formatted = args.formatted.read_text()

    def replaced(before, after):
        assert formatted.count(before) == 1, before
        return formatted.replace(before, after, 1)

    variants = {
        'original': original, 'formatted': formatted,
        'comment_negative': replaced('The episode drill-down engine + UI',
                                     'The episode drill-down engine and UI'),
        'trailing_comment_negative': formatted + '\n// changed trailing comment\n',
        'literal_negative': replaced("'catalog-ep-season'", "'changed-season'"),
        'mandatory_comma_negative': replaced(
            'int epIndex, int episodeCount, int generation',
            'int epIndex, int episodeCount int generation'),
        'deleted_token_negative': replaced(
            'super.initState();', 'initState();'),
        'required_record_before': 'final value = (1);',
        'required_record_after': 'final value = (1,);',
    }
    # Syntax-valid mandatory-token negatives use scanner output; the inherited
    # adapter correctly rejects syntactically invalid missing commas/semicolons.
    invalid = {'mandatory_comma_negative': variants.pop('mandatory_comma_negative')}
    parsed = json.loads(subprocess.run(
        ['dart', str(kernel)], input=json.dumps(variants), text=True,
        capture_output=True, check=True).stdout)
    sys.path.insert(0, str(root / 'dev/tool'))
    from check_verbatim_moves import parse
    declarations = parse({'original': original, 'formatted': formatted},
                         args.parser_package)
    for name in ('original', 'formatted'):
        leaves = [member for declaration in declarations[name]['declarations']
                  for member in (declaration['members'] or [declaration])]
        for site in parsed[name]['optionalCommas']:
            candidates = [leaf for leaf in leaves
                          if leaf['start'] <= site['offset'] < leaf['end']]
            assert candidates, site
            leaf = min(candidates, key=lambda value: value['end'] - value['start'])
            site['owner'] = '.'.join(filter(None, [leaf['owner'], leaf['name']]))

    def normalized(name):
        node = parsed[name]
        optional = {site['offset'] for site in node['optionalCommas']}
        return [token['text'] for token in node['tokens']
                if token['offset'] not in optional]

    assert normalized('original') == normalized('formatted'), \
        'Mandatory tokens, comments or literals differ'
    negatives = {}
    for name in ('comment_negative', 'trailing_comment_negative', 'literal_negative',
                 'deleted_token_negative'):
        assert normalized(name) != normalized('original'), 'Accepted ' + name
        negatives[name] = 'rejected'
    assert normalized('required_record_before') != normalized('required_record_after')
    negatives['required_singleton_record_comma'] = 'rejected'
    for name, text in invalid.items():
        result = subprocess.run(['dart', str(kernel)],
                                input=json.dumps({name: text}), text=True,
                                capture_output=True)
        assert result.returncode != 0, 'Accepted ' + name
        assert 'Bad state: ' + name in result.stderr
        negatives[name] = 'rejected (parser diagnostic)'

    def anchors(name):
        node = parsed[name]
        sites = {site['offset']: site for site in node['optionalCommas']}
        result, mandatory = {}, -1
        for token in node['tokens']:
            if token['offset'] in sites:
                assert token['text'] == ','
                assert mandatory not in result
                result[mandatory] = {**sites[token['offset']], 'anchor': mandatory}
            else:
                mandatory += 1
        return result

    before, after = anchors('original'), anchors('formatted')
    inserted = [after[anchor] for anchor in sorted(after.keys() - before.keys())]
    removed = [before[anchor] for anchor in sorted(before.keys() - after.keys())]
    assert len(inserted) == 38, len(inserted)
    assert len(removed) == 4, len(removed)
    # The only comma moved over a parenthesis belongs to completion publishing.
    relocating_insert = [site for site in inserted
                         if site['owner'] == 'EpisodesPanelState._publishSeriesCompletion'
                         and site['node'] == 'ArgumentListImpl']
    relocating_remove = [site for site in removed
                         if site['owner'] == 'EpisodesPanelState._publishSeriesCompletion'
                         and site['node'] == 'ArgumentListImpl']
    assert len(relocating_insert) == len(relocating_remove) == 1
    relocation = {'from': relocating_remove[0], 'to': relocating_insert[0]}
    subprocess.run(['dart', 'format', '--output=none', '--set-exit-if-changed',
                    str(args.formatted)], check=True, stdout=subprocess.DEVNULL)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({
        'original_revision': args.original,
        'source': SOURCE,
        'adapter': str(adapter.relative_to(root)),
        'original_sha256': hashlib.sha256(original.encode()).hexdigest(),
        'formatted_sha256': hashlib.sha256(formatted.encode()).hexdigest(),
        'mandatory_tokens_comments_literals_equal': True,
        'inserted_optional_commas': inserted,
        'removed_optional_commas': removed,
        'inserted_count': len(inserted), 'removed_count': len(removed),
        'relocations': [relocation], 'negative_results': negatives,
        'format_idempotent': True,
    }, indent=2) + '\n')
    print('PASS: mandatory tokens/comments/literals equal; '
          '38 inserted / 4 removed optional commas, including one relocation; '
          '6 negatives rejected')


if __name__ == '__main__':
    main()
