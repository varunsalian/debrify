#!/usr/bin/env python3
"""Prove single declaration ownership/body/bindings and return literal-safe R.

The fully verified R text is the reversal, in original manifest order. This
avoids rewriting comments, literals or a local with a renamed field's name.
"""
import argparse,csv,hashlib,json,subprocess
from pathlib import Path
from check_verbatim_moves import ROOT,ensure_parser_package,parse
from check_settings_moves import all_nodes,check,configured


def validate(original,sources,rows,config,package):
    with configured(config):
        lookup=all_nodes(parse(sources,package,occurrence_bindings=True))
    for r in rows:
        owner,_,name=r['original_name'].rpartition('.')
        retained=(config['source'],owner,name or r['original_name'])
        destination=(r['destination_file'],r['destination_class'],r['new_name'])
        present={k for k in [retained,destination] if k in lookup}
        # build is the only registered retained forwarder.
        if r['original_name'] in config.get('forwarders',{}) and destination in present:
            present.discard(retained)
        if len(present)!=1:raise ValueError('Missing/duplicate declaration ownership: '+r['original_name'])
    errors=check(original,sources,rows,config['source'],package,context_guard=True,config=config)
    if errors:raise ValueError('\n'.join(errors))
    return original


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json',action='store_true')
    parser.add_argument('--parser-package',type=Path,required=True)
    args=parser.parse_args()
    if '.dart_tool/edit_profile_parser/' not in str(args.parser_package):
        parser.error('reader requires its worktree-local isolated edit_profile parser')
    ensure_parser_package(args.parser_package.parents[1],args.parser_package)
    config=json.loads((ROOT/'dev/tool/edit_profile_checker_config.json').read_text())
    rows=list(csv.DictReader((ROOT/'dev/tool/edit_profile_manifest.tsv').open(),delimiter='\t'))
    original=subprocess.check_output(['git','show',config['baseline']+':'+config['source']],cwd=ROOT,text=True)
    sources={config['source']:(ROOT/config['source']).read_text()}
    sources.update({p.relative_to(ROOT).as_posix():p.read_text() for p in (ROOT/config['feature']).rglob('*.dart')})
    validated=validate(original,sources,rows,config,args.parser_package)
    print(json.dumps({'R':config['baseline'],'files':list(sources),'source':validated}) if args.json else validated,end='\n' if args.json else '')

if __name__=='__main__':main()
