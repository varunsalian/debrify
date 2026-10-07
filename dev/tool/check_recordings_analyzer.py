#!/usr/bin/env python3
"""Require the nine recordings alias warnings by constructor/parameter count.

Run beside check_analyzer_allowlist.py on the same analyzer output. Other
features and diagnostic rules remain the shared helper's responsibility.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import re

from check_verbatim_moves import ROOT, ensure_parser_package, parse

FEATURE = 'lib/features/recordings/presentation/'
LINE = re.compile(r'^\s*(error|warning|info) • (.*) • (\S+?):(\d+):(\d+) • (\S+)\s*$')
PARAMETER = re.compile(
    r"A value for optional parameter '([^']+)' isn't ever given\. "
    r'Try removing the unused parameter$'
)
SITES = [
    ('buttons', '_HubButton', 'filled'),
    ('buttons', '_HubButton', 'danger'),
    ('buttons', '_HubButton', 'autofocus'),
    ('buttons', '_HubButton', 'onDown'),
    ('buttons', '_HubIconButton', 'onDown'),
    ('chrome', '_HubBar', 'onScheduleDown'),
    ('chrome', '_SectionHeader', 'chip'),
    ('chrome', '_SectionHeader', 'action'),
    ('library_row', '_LibraryRow', 'focusNode'),
]


def message(parameter):
    return (f"A value for optional parameter '{parameter}' isn't ever given. "
            'Try removing the unused parameter')


def identity(file, constructor, parameter):
    return ('warning', 'unused_element_parameter', file, constructor,
            parameter, message(parameter))


def parameter_sites(sources, package):
    """Map physical parameter-name tokens to AST constructor identities."""
    sites = {}
    for file, unit in parse(sources, package).items():
        for declaration in unit['declarations']:
            for member in declaration['members']:
                if 'ConstructorDeclaration' not in member['kind']:
                    continue
                tokens = [t for t in member['tokens'] if not t['comment']]
                opening = next(i for i, t in enumerate(tokens) if t['text'] == '(')
                depth = 0
                for i in range(opening, len(tokens)):
                    token = tokens[i]
                    depth += (token['text'] == '(') - (token['text'] == ')')
                    if depth == 0:
                        break
                    if (token['text'] in member['parameterNames'] and i >= 2
                            and [t['text'] for t in tokens[i-2:i]] == ['this', '.']):
                        key = (file, token['offset'])
                        assert key not in sites, 'Ambiguous parameter location'
                        sites[key] = identity(
                            file, declaration['name']+'.'+member['name'], token['text'])
    return sites


def offset(source, line, column):
    lines = source.splitlines(keepends=True)
    if not (1 <= line <= len(lines) and 1 <= column <= len(lines[line-1])):
        raise ValueError('Invalid diagnostic location')
    return sum(map(len, lines[:line-1])) + column - 1


def check(text, sources, sites):
    expected = Counter(identity(FEATURE+f'recordings_hub_{file}.dart',
                                constructor+'.'+constructor, parameter)
                       for file, constructor, parameter in SITES)
    observed = Counter()
    errors = []
    for line in text.splitlines():
        match = LINE.match(line)
        if not match:
            continue
        severity, diagnostic, file, ln, col, rule = match.groups()
        if not (file.startswith(FEATURE) and rule == 'unused_element_parameter'):
            continue
        parameter = PARAMETER.fullmatch(diagnostic)
        try:
            site = sites[(file, offset(sources[file], int(ln), int(col)))]
        except (KeyError, ValueError):
            errors.append('Not a recordings constructor parameter: '+line.strip())
            continue
        if (severity != 'warning' or not parameter
                or parameter.group(1) != site[4] or diagnostic != site[5]):
            errors.append('Constructor parameter/message mismatch: '+line.strip())
            continue
        observed[site] += 1
    errors.extend(f'Missing {count}: {key}' for key, count in (expected-observed).items())
    errors.extend(f'Unexpected {count}: {key}' for key, count in (observed-expected).items())
    return errors


def self_test(sources, sites):
    expected = [identity(FEATURE+f'recordings_hub_{file}.dart',
                         constructor+'.'+constructor, parameter)
                for file, constructor, parameter in SITES]
    locations = {site: (file, at) for (file, at), site in sites.items()}

    def diagnostic(site, location=None):
        file, at = location or locations[site]
        source = sources[file]
        line = source.count('\n', 0, at)+1
        column = at-source.rfind('\n', 0, at)
        return f'warning • {site[5]} • {file}:{line}:{column} • unused_element_parameter'

    good = [diagnostic(site) for site in expected]
    assert not check('\n'.join(good), sources, sites)
    unrelated = diagnostic(expected[0]).replace(FEATURE, 'lib/features/another/')
    assert not check('\n'.join(good+[unrelated]), sources, sites)
    wrong_constructor = good.copy()
    wrong_constructor[3] = diagnostic(expected[3], locations[expected[4]])
    wrong_parameter = good.copy()
    wrong_parameter[0] = diagnostic(expected[0], locations[expected[1]])
    outside_parameter = good.copy()
    file = expected[0][2]
    outside_parameter[0] = diagnostic(expected[0], (file, sources[file].index('filled;')))
    negatives = [
        ('one missing', good[:-1]),
        ('one duplicated', good+[good[0]]),
        ('onDown on the wrong constructor', wrong_constructor),
        ('parameter and message disagree', wrong_parameter),
        ('field instead of constructor parameter', outside_parameter),
    ]
    report = []
    for label, lines in negatives:
        errors = check('\n'.join(lines), sources, sites)
        assert errors, 'Accepted '+label
        report.append(dict(label=label, errors=errors))
        print('Recordings analyzer rejected: '+label)
    print('Recordings analyzer self-test: 2 positives / 5 rejections')
    return dict(positives=2, rejections=report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('analyzer', type=Path, nargs='?')
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if not args.self_test and not args.analyzer:
        parser.error('analyzer output is required')
    package = args.parser_package.resolve()
    ensure_parser_package(package.parent.parent, package)
    sources = {FEATURE+f'recordings_hub_{name}.dart':
               (ROOT/FEATURE/f'recordings_hub_{name}.dart').read_text()
               for name in sorted({row[0] for row in SITES})}
    sites = parameter_sites(sources, package)
    if args.self_test:
        report = self_test(sources, sites)
        if args.report:
            args.report.write_text(json.dumps(report, indent=2)+'\n')
    if args.analyzer:
        errors = check(args.analyzer.read_text(), sources, sites)
        if errors:
            raise AssertionError('\n'.join(errors))
        print('Recordings analyzer: exactly 9 constructor/parameter warnings, counts unchanged')


if __name__ == '__main__':
    main()
