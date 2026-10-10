"""One pinned, offline Kotlin toolchain lookup for PSI and compiled fixtures."""
import hashlib
import json
import os
from pathlib import Path
import shutil

from android_junit_evidence import evidence_root as native_evidence_root

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = json.loads((Path(__file__).with_name('kotlin_artifacts.json')).read_text())


def java_home():
    if os.environ.get('JAVA_HOME'):
        return Path(os.environ['JAVA_HOME'])
    studio = Path('/Applications/Android Studio.app/Contents/jbr/Contents/Home')
    if studio.is_dir():
        return studio
    java = shutil.which('javac')
    if not java:
        raise ValueError('JDK 21 required: set JAVA_HOME or put javac on PATH')
    return Path(java).resolve().parent.parent


JBR = java_home()


def evidence_root(root):
    override = os.environ.get('TVPLAYER_EVIDENCE_ROOT')
    return Path(override).resolve() if override else native_evidence_root(root)


def gradle_cache():
    home = Path(os.environ.get('GRADLE_USER_HOME', str(Path.home() / '.gradle')))
    return home / 'caches/modules-2/files-2.1'


def artifact_matches(row):
    return sorted((gradle_cache() / row['group'] / row['artifact'] / row['version']).glob('*/*.jar'))


def verify_artifact(path, row):
    if hashlib.sha256(path.read_bytes()).hexdigest() != row['sha256']:
        raise ValueError('pinned Kotlin artifact checksum mismatch: ' + str(path))


def kotlin_jars(*, include_reflect=True):
    jars = []
    for row in ARTIFACTS:
        if not include_reflect and row['artifact'] == 'kotlin-reflect':
            continue
        matches = artifact_matches(row)
        if len(matches) != 1:
            raise ValueError(f'offline Kotlin artifact unavailable/ambiguous: {row["artifact"]}:{row["version"]}')
        verify_artifact(matches[0], row)
        jars.append(matches[0])
    return jars
