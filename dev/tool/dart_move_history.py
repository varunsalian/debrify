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


def earlier_manifests(manifest, root=ROOT):
    """Load every applied earlier phase from the same phase-base revision."""
    revision = manifest['base']
    directory = manifest.get('history_directory', 'dev/tool/dart_moves')
    paths = subprocess.check_output(['git', '-C', str(root), 'ls-tree', '-r', '--name-only',
                                     revision, '--', directory], text=True).splitlines()
    approved, phases = [], set()
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
            approved.append(prior)
    if phases != set(range(1, manifest['phase'])):
        raise ValueError('missing historical phase manifests')
    return sorted(approved, key=lambda p: p['phase'])


def earlier_sources(manifest, root=ROOT):
    """A caller cannot omit a destination by omitting it from a whitelist."""
    approved = {path for prior in earlier_manifests(manifest, root)
                for path in prior['destinations']}
    return {p: git_text(manifest['base'], p, root) for p in sorted(approved)}


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


# Revision at which each applied phase is checked as history (the CI `--at`
# list). Since Phase 21b the live tree carries later declared edits in earlier
# destinations (the P21 manifest's earlier_patches, proved by the current P21
# check), so a historical self-test compares a phase's earlier destinations
# at its own applied revision, not in the live tree.
APPLIED_AT = {1: '31a347ad2', 2: 'fc24e32ae', 3: '890df14d8', 4: '315028407', 5: 'ea7901ead',
              6: '2defa5100', 7: '491bf1fea', 8: '0df6ccd4e', 9: '5c7b704bd', 10: '7fdf59370',
              11: '0c2fb62e8', 12: '1d7699d2e', 13: '238df16f4', 14: 'be4cd78aa', 15: 'ed7c6717a',
              16: 'c094c864c', 17: '249566376', 18: '46bc00ce7', 19: '0f5bfb161', 20: '5214f7a7e'}


def applied_sources(manifest, root=ROOT):
    revision = APPLIED_AT[manifest['phase']]
    return {p: git_text(revision, p, root) for p in earlier_sources(manifest, root)}
