"""Lossless Dart token/declaration utilities for the verbatim storage split.

This is a lexer, not a Dart semantic analyzer. It exposes executable string
interpolations while preserving every literal byte, and rejects unsupported
declaration shapes rather than guessing. Flutter analyze checks name resolution.
"""
from dataclasses import dataclass
from pathlib import Path
import csv
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
LEGACY = 'lib/services/storage_service.dart'
RESET = 'lib/services/storage/storage_profile_caches.dart'
BASE = '072407c3'
MAP = ROOT / 'dev/tool/storage_member_map.tsv'
ENUM_FILES = ('lib/models/ambient_trailer_surface.dart',
              'lib/models/tv_render_quality.dart')


@dataclass(frozen=True)
class Token:
    text: str
    start: int
    end: int
    kind: str = 'code'


def tokens(source):
    out = []

    def emit(a, b, kind='code'):
        out.append(Token(source[a:b], a, b, kind))

    def string(i, raw=False):
        start = i
        q = i + int(raw)
        quote = source[q:q+3] if source[q:q+3] in ('"""', "'''") else source[q]
        i = q + len(quote)
        while i < len(source):
            if source.startswith(quote, i):
                i += len(quote)
                emit(start, i, 'literal')
                return i
            if not raw and source[i] == '\\':
                i += 2
            elif not raw and source.startswith('${', i):
                emit(start, i+2, 'literal')
                i = code(i+2, interpolation=True)
                start = i-1
            elif not raw and source[i] == '$' and re.match(r'[A-Za-z_]', source[i+1:i+2]):
                emit(start, i+1, 'literal')
                end = i+1
                while end < len(source) and re.match(r'[\w$]', source[end]):
                    end += 1
                emit(i+1, end)
                i = start = end
            else:
                i += 1
        raise ValueError(f'Unterminated string at {q}')

    def code(i, interpolation=False):
        braces = 0
        while i < len(source):
            c = source[i]
            if c.isspace():
                i += 1
            elif source.startswith('//', i):
                end = source.find('\n', i)
                end = len(source) if end < 0 else end
                emit(i, end, 'comment')
                i = end
            elif source.startswith('/*', i):
                a, depth = i, 1
                i += 2
                while depth and i < len(source):
                    if source.startswith('/*', i):
                        depth += 1
                        i += 2
                    elif source.startswith('*/', i):
                        depth -= 1
                        i += 2
                    else:
                        i += 1
                if depth:
                    raise ValueError(f'Unterminated comment at {a}')
                emit(a, i, 'comment')
            elif c in ('"', "'") or (c == 'r' and source[i+1:i+2] in ('"', "'")):
                i = string(i, c == 'r')
            elif c == '}' and interpolation and braces == 0:
                return i+1
            elif re.match(r'[A-Za-z_$]', c):
                a = i
                i += 1
                while i < len(source) and re.match(r'[\w$]', source[i]):
                    i += 1
                emit(a, i)
            else:
                emit(i, i+1)
                braces += (c == '{') - (c == '}')
                i += 1
        if interpolation:
            raise ValueError('Unterminated interpolation')
        return i

    code(0)
    return out


def code_tokens(source):
    return [t for t in tokens(source) if t.kind == 'code']


@dataclass
class Member:
    name: str
    kind: str
    start: int
    end: int
    move_start: int
    declaration: str
    text: str
    line: int


def members(source, class_name='StorageService'):
    ts = [t for t in tokens(source) if t.kind != 'comment']
    opening = next(i+2 for i in range(len(ts)-2)
                   if ts[i].text == 'class' and ts[i+1].text == class_name)
    assert ts[opening].text == '{', class_name
    depth, starts, close = 1, [], None
    for i in range(opening+1, len(ts)):
        t = ts[i]
        if t.kind != 'code':
            continue
        if depth == 1 and t.text == 'static':
            starts.append(i)
        depth += (t.text == '{') - (t.text == '}')
        if depth == 0:
            close = i
            break
    assert close is not None
    out, previous = [], ts[opening].end
    for si in starts:
        angle = 0
        header_end = None
        for i in range(si+1, close):
            if ts[i].kind != 'code':
                continue
            v = ts[i].text
            if angle == 0 and v in ('(', '=', ';'):
                header_end = i
                break
            angle += (v == '<') - (v == '>')
        assert header_end is not None
        paren = square = curly = 0
        field = ts[header_end].text != '('
        expression_body = False
        end = None
        for i in range(header_end, close):
            t = ts[i]
            if t.kind != 'code':
                continue
            v = t.text
            if not (paren or square or curly):
                if v == '=' and i+1 < len(ts) and ts[i+1].text == '>':
                    expression_body = True
                if v == ';':
                    end = i
                    break
            paren += (v == '(') - (v == ')')
            square += (v == '[') - (v == ']')
            curly += (v == '{') - (v == '}')
            if v == '}' and not (paren or square or curly) and not field and not expression_body:
                end = i
                break
        assert end is not None, ts[si].start
        h = ts[si:header_end]
        words = [t.text for t in h if re.fullmatch(r'[A-Za-z_]\w*', t.text)]
        name = words[-1]
        kind = ('getter' if 'get' in words else
                'const' if 'const' in words else
                'field' if field or header_end is None else 'method')
        if kind == 'const' and name.startswith('_') and len(words) == 4 and words[2] == 'String':
            kind = 'key'
        start, finish = ts[si].start, ts[end].end
        # Keep annotations with declarations; comments travel losslessly too.
        gap = source[previous:start]
        annotation = re.search(r'(?m)^\s*@', gap)
        declaration_start = previous + annotation.start() if annotation else start
        out.append(Member(name, kind, declaration_start, finish, previous,
                          source[declaration_start:finish], source[previous:finish],
                          source.count('\n', 0, start)+1))
        previous = finish
    assert len({m.name for m in out}) == len(out), 'Duplicate member names'
    return out


def type_declaration(source, name):
    ts = code_tokens(source)
    i = next(i for i in range(len(ts)-1)
             if ts[i].text in ('class', 'enum') and ts[i+1].text == name)
    a, depth = ts[i].start, 0
    for t in ts[i+2:]:
        depth += (t.text == '{') - (t.text == '}')
        if t.text == '}' and depth == 0:
            return source[a:t.end]
    raise ValueError(name)


def original():
    return subprocess.run(['git', 'show', f'{BASE}:{LEGACY}'], cwd=ROOT,
                          capture_output=True, text=True, check=True).stdout


def read_map():
    with MAP.open() as f:
        rows = list(csv.DictReader(f, delimiter='\t'))
    for r in rows:
        r['step'] = int(r['step'])
    return rows


RETIRED = ROOT / 'dev/tool/storage_retired.tsv'


def retired_members():
    """Original StorageService members deliberately deleted later as dead code.

    Each entry must name a mapped member whose destination file no longer
    exists, so retirement can't hide a live declaration or a typo.
    """
    with RETIRED.open() as f:
        entries = list(csv.DictReader(f, delimiter='\t'))
    mapped = {r['member']: r for r in read_map()}
    for e in entries:
        row = mapped.get(e['member'])
        assert row is not None, ('retired member not in map', e['member'])
        assert row['file'] == e['file'], ('retired file mismatch', e['member'])
        assert not (ROOT / e['file']).exists(), ('retired file still exists', e['file'])
        assert e['reason'].strip(), ('retired member needs a reason', e['member'])
    return {e['member'] for e in entries}


def tracked_dart():
    return subprocess.run(['git', 'ls-files', '*.dart'], cwd=ROOT,
                          capture_output=True, text=True, check=True).stdout.splitlines()


def source_paths():
    paths = set((ROOT / 'lib/services/storage').rglob('*.dart'))
    paths.update(ROOT / p for p in ENUM_FILES if (ROOT / p).exists())
    if (ROOT / LEGACY).exists():
        paths.add(ROOT / LEGACY)
    return sorted(paths)


def replacements(source, edits):
    for a, b, value in sorted(edits, reverse=True):
        source = source[:a] + value + source[b:]
    return source


def normalized(source):
    # Token boundaries matter, and literal bytes (including spaces) are exact.
    return [(t.kind, t.text) for t in tokens(source) if t.kind != 'comment']
