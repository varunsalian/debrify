#!/usr/bin/env python3
"""Read live original responsibilities through their registered move locations."""
import csv
import json
import re
import subprocess
from pathlib import Path
from check_verbatim_moves import parse
from check_settings_moves import ROOT, all_nodes, configured, declaration_tokens, partition_virtual


def inventory():
    config = json.loads((ROOT/'dev/tool/playback_settings_checker_config.json').read_text())
    rows = list(csv.DictReader((ROOT/'dev/tool/playback_settings_manifest.tsv').open(), delimiter='\t'))
    # The test owns a checkout-local kernel. It never initializes/recompiles
    # a parser in the shared evidence namespace used by concurrent checkers.
    package = ROOT/'.dart_tool/playback_settings_source_parser/.dart_tool/package_config.json'
    if not package.exists():
        # Fresh CI clones initialize only this checkout's
        # isolated tooling package from the checked-in lock, never the app.
        tooling = package.parent.parent
        tooling.mkdir(parents=True, exist_ok=True)
        (tooling/'pubspec.yaml').write_text(
            "name: refactor_verbatim_parser\nenvironment:\n"
            "  sdk: '>=3.12.0 <4.0.0'\ndependencies:\n  analyzer: 14.3.0\n")
        (tooling/'pubspec.lock').write_text((ROOT/'dev/tool/verbatim_parser.pubspec.lock').read_text())
        subprocess.run(['dart','pub','get','--enforce-lockfile','--directory',str(tooling)],
                       check=True, stdout=subprocess.DEVNULL)
    source = config['source']
    sources = {source:(ROOT/source).read_text()}
    sources.update({p.relative_to(ROOT).as_posix():p.read_text() for p in (ROOT/config['feature']).rglob('*.dart')})
    lookup = all_nodes(parse(sources, package))
    members = {}
    with configured(config):
        for row in rows:
            owner, _, name = row['original_name'].rpartition('.')
            node = lookup.get((row['destination_file'],row['destination_class'],row['new_name'])) or lookup.get((source,owner,name))
            if node is None:
                raise ValueError('Missing original responsibility: '+row['original_name'])
            if name == '_externalPlayerSettings' and node['owner'] != owner:
                partition = json.loads((ROOT/config['sidecars']['partitions']).read_text())['partitions'][row['original_name']]
                node = partition_virtual(node,partition,lookup,sources,package)
            members[name] = ' '.join(declaration_tokens(node,rows,row))
    predicates = {name: re.findall(r'(?:Platform|PlatformUtil) \. \w+|\bisAndroidTv\b',text) for name,text in members.items()}
    predicates = {k:v for k,v in predicates.items() if v}
    load = members['_loadSettings']
    calls = re.findall(r'(?:\w+(?:Service(?:Extension)?|Storage)|AndroidNativeDownloader) \. (?:instance \. )?(\w+) \(',load)
    detectors = re.findall(r'((?:ExternalPlayerService|(?:Linux|Windows)ExternalPlayerServiceExtension|AndroidNativeDownloader) \. (?:detectInstalled\w+|isTelevision) \([^)]*\))', load)
    return {
        'detector_sites_arguments': detectors,
        'detection_prefix': load.split('String vrScreen')[0],
        'predicates':predicates,
        'listeners':re.findall(r'(\w+FocusNode) \. addListener \(',members['initState']),
        'disposals':re.findall(r'(\w+) \. dispose \(',members['dispose']),
        'load_calls':calls,
        'lifecycle_prefix':members['initState'].split('addListener')[0],
        'self_push':members['_openPlayerSettings'],
        # The named root-build exception removes only @override. Pin the
        # unsupported branch itself, independently of that registered header.
        'unsupported':members['build'].split('{', 1)[1].split('if ( loading )')[0],
        'tv_aspect_setter':members['_setDefaultAspectIndex'],
        'appearance':members['_playerAppearance'],
        'tv_textfields':{name:len(re.findall(r'\bTvTextField \(',text)) for name,text in members.items() if 'TvTextField (' in text},
        'key_events':{name:len(re.findall(r'\bonKeyEvent :',text)) for name,text in members.items() if 'onKeyEvent :' in text},
    }


if __name__ == '__main__':
    print(json.dumps(inventory(), sort_keys=True, indent=2))
