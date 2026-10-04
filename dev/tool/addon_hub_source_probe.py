#!/usr/bin/env python3
"""Resolve complete production bodies for frozen addon-hub source contracts."""
import argparse,csv,json,subprocess
from pathlib import Path
from check_settings_moves import all_nodes,configured,declaration_tokens,remove_context_exceptions
from check_verbatim_moves import parse
ROOT=Path(__file__).resolve().parents[2]


def main():
    args=argparse.ArgumentParser();args.add_argument('--parser-package',type=Path,required=True);options=args.parse_args()
    package=options.parser_package.resolve()
    from check_verbatim_moves import parser_lock
    with parser_lock(package.parent.parent):
      if not package.exists():
        directory=package.parent.parent;directory.mkdir(parents=True,exist_ok=True)
        (directory/'pubspec.yaml').write_text("name: refactor_verbatim_parser\nenvironment:\n  sdk: '>=3.12.0 <4.0.0'\ndependencies:\n  analyzer: 14.3.0\n")
        (directory/'pubspec.lock').write_bytes((ROOT/'dev/tool/verbatim_parser.pubspec.lock').read_bytes())
        subprocess.run(['dart','pub','get','--enforce-lockfile','--directory',str(directory)],stdout=subprocess.DEVNULL,check=True)
    config=json.loads((ROOT/'dev/tool/addon_hub_checker_config.json').read_text())
    rows=list(csv.DictReader((ROOT/'dev/tool/addon_hub_manifest.tsv').open(),delimiter='\t'))
    source=config['source'];sources={source:(ROOT/source).read_text()}
    # Unconditional feature scan. An empty pre-extraction feature has no leaves.
    sources.update({p.relative_to(ROOT).as_posix():p.read_text() for p in (ROOT/config['feature']).rglob('*.dart')})
    lookup=all_nodes(parse(sources,package));result={}
    exceptions=json.loads((ROOT/config['sidecars']['context_exceptions']).read_text())['sites']
    with configured(config):
        for row in rows:
            key=(row['destination_file'],row['destination_class'],row['new_name']);node=lookup.get(key)
            if node is None:
                owner,_,name=row['original_name'].rpartition('.')
                node=lookup[(source,owner,name or row['original_name'])]
            sites=[s for s in exceptions if (s['file'],s['owner'],s['method'])==key]
            if sites:node=remove_context_exceptions(node,sites,rows,row)
            result[row['original_name']]=declaration_tokens(node,rows,row)
    print(json.dumps(result))

if __name__=='__main__':main()
