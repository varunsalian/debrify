"""Parse Kotlin sources with the real Kotlin PSI (dev/tool/kotlin_psi/KotlinPsi.java)."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

from kotlin_toolchain import evidence_root, JBR, kotlin_jars

ROOT = Path(__file__).resolve().parents[2]
PARSE_CACHE = {}


def parse(sources, *, lexer_only=False):
    """Compile offline under a lock, then parse all inputs in one JVM."""
    missing = {key: value for key, value in sources.items() if (value, lexer_only) not in PARSE_CACHE}
    if not missing:
        return {key: PARSE_CACHE[value, lexer_only] for key, value in sources.items()}
    jars = kotlin_jars(include_reflect=False)
    cp = os.pathsep.join(map(str, jars))
    folder = evidence_root(ROOT) / 'psi'
    folder.mkdir(parents=True, exist_ok=True)
    adapter = ROOT / 'dev/tool/kotlin_psi/KotlinPsi.java'
    digest = hashlib.sha256(adapter.read_bytes() + cp.encode()).hexdigest()
    with (folder / 'build.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        stamp = folder / 'build.sha256'
        if not stamp.exists() or stamp.read_text() != digest:
            subprocess.run([str(JBR / 'bin/javac'), '-cp', cp, '-d', str(folder), str(adapter)], check=True)
            stamp.write_text(digest)
    with tempfile.TemporaryDirectory(dir=folder) as directory:
        paths = []
        for index, source in enumerate(missing.values()):
            path = Path(directory) / f'input{index}.kt'
            path.write_text(source)
            paths.append(str(path))
        result = subprocess.run([str(JBR / 'bin/java'), '-cp', str(folder) + os.pathsep + cp,
                                 'KotlinPsi', *(['--lexer-only'] if lexer_only else []), *paths], text=True, capture_output=True)
        if result.returncode:
            raise ValueError('Kotlin PSI failed: ' + result.stderr)
        for value, unit in zip(missing.values(), json.loads(result.stdout)):
            PARSE_CACHE[value, lexer_only] = unit
        return {key: PARSE_CACHE[value, lexer_only] for key, value in sources.items()}


def walk(nodes):
    for node in nodes:
        yield node
        yield from walk(node['children'])


def members(node):
    starts = set(map(int, node['body_member_starts']))
    return [child for child in node['children'] if child['start'] in starts]
