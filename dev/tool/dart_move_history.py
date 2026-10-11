"""Same-revision inputs and history-derived current-tree destination coverage."""
import json
from pathlib import Path
import subprocess

from check_verbatim_moves import ROOT, parse
from check_settings_moves import compare_explicit_tokens


def git_text(revision, path, root=ROOT):
    return subprocess.check_output(['git', '-C', str(root), 'show', revision + ':' + path], text=True)


def load_manifest(path, revision=None, root=ROOT):
    path = Path(path)
    relative = path.relative_to(root).as_posix() if path.is_absolute() else path.as_posix()
    read = lambda p: git_text(revision, p, root) if revision else (root / p).read_text()
    manifest = json.loads(read(relative))
    # Sidecars use repository-relative paths and are always read with the manifest.
    for key, sidecar in manifest.pop('sidecars', {}).items():
        if key in manifest:
            raise ValueError('duplicate inline/sidecar input: ' + key)
        manifest[key] = json.loads(read(sidecar))
    return manifest


def earlier_sources(manifest, root=ROOT):
    """A caller cannot omit a destination by omitting it from a whitelist."""
    revision = manifest['base']
    directory = manifest.get('history_directory', 'dev/tool/dart_moves')
    paths = subprocess.check_output(['git', '-C', str(root), 'ls-tree', '-r', '--name-only',
                                     revision, '--', directory], text=True).splitlines()
    approved, phases = set(), set()
    for path in paths:
        if not path.endswith('.json'):
            continue
        candidate = json.loads(git_text(revision, path, root))
        if not isinstance(candidate, dict) or candidate.get('schema') != 1 or 'series' not in candidate:
            continue  # Sidecars and fixture data are not phase manifests.
        prior = load_manifest(path, revision, root)
        if prior.get('series') != manifest.get('series') or prior.get('status') != 'applied':
            continue
        if prior['phase'] < manifest['phase']:
            if prior['phase'] in phases:
                raise ValueError('duplicate historical phase')
            phases.add(prior['phase'])
            approved.update(prior['destinations'])
    if phases != set(range(1, manifest['phase'])):
        raise ValueError('missing historical phase manifests')
    return {p: git_text(revision, p, root) for p in sorted(approved)}


def check_earlier(manifest, package, current=None, root=ROOT):
    baseline = earlier_sources(manifest, root)
    edits = manifest.get('earlier_patches', {})
    if edits.keys() - baseline.keys():
        return ['earlier patch outside history-derived source set']
    actual = current if current is not None else {p: (root / p).read_text() for p in baseline}
    if actual.keys() != baseline.keys():
        return ['earlier destination source set changed']
    parsed = parse({**{'base:' + p: t for p, t in baseline.items()}, **actual}, package,
                   ownership=True)
    errors = []
    for path in baseline:
        spec = edits.get(path, {})
        if spec and (not spec.get('reason') or not spec.get('review') or not spec.get('patches')):
            errors.append('earlier patches require reason, review and exact edits: ' + path)
        before, after = parsed['base:' + path], parsed[path]
        left = dict(tokens=before['unitTokens'], formatCommas=before['unitFormatCommas'])
        right = dict(tokens=after['unitTokens'], formatCommas=after['unitFormatCommas'])
        errors.extend(compare_explicit_tokens(left, right, spec.get('patches', []),
                                               'earlier destination: ' + path))
    return errors
