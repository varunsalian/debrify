#!/usr/bin/env python3
"""Whole-file vplayer proof using the existing catalog AST/comma adapter."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from check_verbatim_moves import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--original', required=True)
    parser.add_argument('--formatted', type=Path, default=Path('lib/screens/video_player_screen.dart'))
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    source = 'lib/screens/video_player_screen.dart'
    original = subprocess.check_output(['git', 'show', args.original + ':' + source], cwd=ROOT, text=True)
    formatted = args.formatted.read_text()
    kernel = args.parser_package.parent / 'vplayer_format_proof.dill'
    subprocess.run(['dart', 'compile', 'kernel', '--packages=' + str(args.parser_package),
                    '-o', str(kernel), str(ROOT / 'dev/tool/catalog_detail_format_proof.dart.txt')],
                   check=True, stdout=subprocess.DEVNULL)
    variants = dict(original=original, formatted=formatted,
                    required_record_before='final value = (1);', required_record_after='final value = (1,);',
                    comment_negative=formatted + '\n// edited comment\n',
                    literal_negative=formatted.replace('0xFF', '0xFE', 1))
    parsed = json.loads(subprocess.run(['dart', str(kernel)], input=json.dumps(variants),
                                      capture_output=True, text=True, check=True).stdout)
    def normalized(key):
        node = parsed[key]
        optional = {s['offset'] for s in node['optionalCommas']}
        return [t['text'] for t in node['tokens'] if t['offset'] not in optional]
    assert normalized('original') == normalized('formatted'), 'non-format token/comment/literal difference'
    for key in ['comment_negative', 'literal_negative']:
        assert normalized(key) != normalized('original'), 'accepted ' + key
    assert normalized('required_record_before') != normalized('required_record_after')
    def sites(key):
        node = parsed[key]
        optional = {s['offset']: s for s in node['optionalCommas']}
        result, anchor = {}, 0
        for token in node['tokens']:
            if token['offset'] in optional:
                result[anchor] = optional[token['offset']]
            else:
                anchor += 1
        return result
    before, after = sites('original'), sites('formatted')
    idempotent = subprocess.run(['dart', 'format', '--output=none', '--set-exit-if-changed', str(args.formatted)],
                                capture_output=True, text=True)
    assert idempotent.returncode == 0, idempotent.stdout
    result = dict(original_revision=args.original, source=source,
                  original_sha256=hashlib.sha256(original.encode()).hexdigest(),
                  formatted_sha256=hashlib.sha256(formatted.encode()).hexdigest(),
                  original_lines=len(original.splitlines()), formatted_lines=len(formatted.splitlines()),
                  inserted_optional_commas=[dict(token_anchor=i, **after[i]) for i in sorted(after.keys() - before.keys())],
                  deleted_optional_commas=[dict(token_anchor=i, **before[i]) for i in sorted(before.keys() - after.keys())],
                  whole_file_tokens_comments_literals_equal=True, idempotent=True,
                  negatives=['comment', 'literal', 'required_singleton_record_comma'])
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(f'PASS: {len(result["inserted_optional_commas"])} inserted, {len(result["deleted_optional_commas"])} deleted optional commas; idempotent')


if __name__ == '__main__':
    main()
