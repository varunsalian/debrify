#!/usr/bin/env python3
"""Stremio TV per-declaration ownership and raw ORIGINAL/current source proof."""
import argparse
import csv
import hashlib
import json
import subprocess
from pathlib import Path
from check_settings_moves import all_nodes, check, configured, check_forwarder
from check_verbatim_moves import ensure_parser_package, original_leaves, parse, split_names
ROOT=Path(__file__).resolve().parents[2]
CONFIG=ROOT/'dev/tool/stremio_tv_checker_config.json'
MANIFEST=ROOT/'dev/tool/stremio_tv_manifest.tsv'

def original_source(config):
    result=subprocess.run(['git','show',config['baseline']+':'+config['source']],cwd=ROOT,text=True,capture_output=True)
    if result.returncode:
        raise ValueError('Missing ORIGINAL Git object '+config['baseline']+': '+result.stderr.strip())
    return result.stdout

def select_sources(config):
    excluded=set(config.get('excluded_feature_files',[]))
    return {config['source']:(ROOT/config['source']).read_text(),**{p.relative_to(ROOT).as_posix():p.read_text() for p in sorted((ROOT/config['feature']).rglob('*.dart')) if p.relative_to(ROOT).as_posix() not in excluded}}

def validate(original,sources,rows,config,package):
    # Exclusions happen before parsing; the existing catalog picker is unrelated.
    sources={p:s for p,s in sources.items() if p not in config.get('excluded_feature_files',[])}
    with configured(config):
        parsed=parse({'<original>':original,**sources},package,occurrence_bindings=True)
        lookup=all_nodes(parsed)
        originals=original_leaves(parsed['<original>']['declarations'],split_names(rows))
        files=[config['source']]
        for row in rows:
            owner,_,name=row['original_name'].rpartition('.')
            retained=(config['source'],owner,name or row['original_name'])
            destination=(row['destination_file'],row['destination_class'],row['new_name'])
            present={k for k in [retained,destination] if k in lookup}
            spec=config.get('forwarders',{}).get(row['original_name'])
            if len(present)==2 and spec:
                errors=check_forwarder(originals[row['original_name']],lookup[retained],row,spec,package)
                if errors:raise ValueError('Invalid validated forwarder: '+row['original_name']+' '+str(errors))
                present.remove(retained)
            if len(present)!=1:
                raise ValueError(('Duplicate' if present else 'Missing')+' declaration ownership: '+row['original_name'])
            actual=present.pop()
            if config.get('completed_step',0)>=config.get('completion_step',7) and destination not in lookup:
                raise ValueError('Completed declaration remains in facade: '+row['original_name'])
            if actual[0] not in files:files.append(actual[0])
        for path in sources:
            if path.startswith(config['feature']+'/') and path not in files and path not in config['scaffolds']:
                raise ValueError('Unregistered extra Stremio TV file: '+path)
        errors=check(original,sources,rows,config['source'],package,context_guard=True,config=config)
        if errors:raise ValueError('\n'.join(errors))
    return files

def read_current(complete=False):
    config=json.loads(CONFIG.read_text())
    if complete:config={**config,'completed_step':7}
    rows=list(csv.DictReader(MANIFEST.open(),delimiter='\t'))
    original=original_source(config);sources=select_sources(config)
    digest=hashlib.sha256(json.dumps(dict(original=original,sources=sources,rows=rows,config=config),sort_keys=True).encode())
    for path in sorted((ROOT/'dev/tool').glob('*.py')):digest.update(path.name.encode());digest.update(path.read_bytes())
    for path in [ROOT/'dev/tool/verbatim_ast.dart.txt',ROOT/'dev/tool/verbatim_parser.pubspec.lock',*[ROOT/p for p in config.get('sidecars',{}).values()]]:digest.update(path.read_bytes())
    cache=ROOT/'.dart_tool/stremio_tv_parser/source_reader_cache';cache.mkdir(parents=True,exist_ok=True)
    snapshot=cache/(digest.hexdigest()+'.json')
    if snapshot.exists():files=json.loads(snapshot.read_text())['files']
    else:
        package=ROOT/'.dart_tool/stremio_tv_parser/source_reader';pc=package/'.dart_tool/package_config.json'
        ensure_parser_package(package,pc)
        files=validate(original,sources,rows,config,pc)
        snapshot.write_text(json.dumps({'files':files})+'\n')
    return {'files':files,'source':original,'current_source':'\n'.join(sources[p] for p in files)}

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--json',action='store_true');parser.add_argument('--complete',action='store_true');args=parser.parse_args()
    result=read_current(args.complete);print(json.dumps(result) if args.json else result['source'],end='\n' if args.json else '')
if __name__=='__main__':main()
