#!/usr/bin/env python3
"""Whole-file scanner proof, permitting only AST-identified formatter commas."""
import argparse
import difflib
import hashlib
import json
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--original', required=True)
    parser.add_argument('--formatted', required=True)
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    adapter = Path(__file__).with_suffix('.dart.txt')
    kernel = args.parser_package.parent / 'merged_detail_format_proof.dill'
    subprocess.run(['dart', 'compile', 'kernel', '--packages=' + str(args.parser_package), '-o', str(kernel), str(adapter)], check=True, stdout=subprocess.DEVNULL)
    source = 'lib/screens/merged_series_detail_screen.dart'
    original = subprocess.run(['git', 'show', args.original + ':' + source], capture_output=True, text=True, check=True).stdout
    formatted = Path(args.formatted).read_text()
    variants = {'original': original, 'formatted': formatted,
                'comment_negative': formatted.replace('Merged series page (experimental', 'Merged movie page (experimental', 1),
                'trailing_comment_negative': formatted + '\n// changed trailing comment\n',
                'literal_negative': formatted.replace('0xFF0B0B0E', '0xFF0B0B0F', 1),
                'required_record_comma_before': 'final value = (1);',
                'required_record_comma_after': 'final value = (1,);'}
    result = subprocess.run(['dart', str(kernel)], input=json.dumps(variants), text=True, capture_output=True, check=True)
    parsed = json.loads(result.stdout)
    def normalized(name):
        node = parsed[name]
        optional = {s['offset'] for s in node['optionalCommas']}
        return [t['text'] for t in node['tokens'] if t['offset'] not in optional]
    assert normalized('original') == normalized('formatted'), 'Non-format token/comment/literal difference'
    for name in ('comment_negative', 'trailing_comment_negative', 'literal_negative'):
        assert normalized(name) != normalized('original'), 'Accepted ' + name
    assert normalized('required_record_comma_before') != normalized('required_record_comma_after')
    before = [t['text'] for t in parsed['original']['tokens']]
    after = [t['text'] for t in parsed['formatted']['tokens']]
    sites = {s['offset']: s for s in parsed['formatted']['optionalCommas']}
    inserted = []
    for op, i, j, k, l in difflib.SequenceMatcher(a=before, b=after, autojunk=False).get_opcodes():
        if op == 'equal': continue
        assert op == 'insert' and after[k:l] == [','], (op, before[i:j], after[k:l])
        token = parsed['formatted']['tokens'][k]
        assert token['offset'] in sites
        inserted.append(sites[token['offset']])
    assert len(inserted) == 25, len(inserted)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({'original_revision': args.original,
        'original_sha256': hashlib.sha256(original.encode()).hexdigest(),
        'formatted_sha256': hashlib.sha256(formatted.encode()).hexdigest(),
        'inserted_optional_commas': inserted,
        'whole_file_tokens_comments_literals_equal': True,
        'negative_results': {'comment': 'rejected', 'trailing_comment': 'rejected', 'literal': 'rejected', 'required_singleton_record_comma': 'rejected'}}, indent=2) + '\n')
    print('Whole-file scanner/comment/literal proof: PASS; 25 AST-identified optional commas; 4 negatives rejected')


if __name__ == '__main__':
    main()
