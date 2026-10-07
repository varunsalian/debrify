"""Validate all live declarations and return their unchanged ORIGINAL bodies."""
import argparse,json,csv,subprocess
from pathlib import Path
from check_verbatim_moves import ROOT,parse,original_leaves,split_names,ensure_parser_package
from check_settings_moves import check,all_nodes

def validate(original,sources,rows,config,package):
 failures=check(original,sources,rows,config['source'],package,context_guard=True,config=config)
 if failures:raise ValueError('\n'.join(failures))
 parsed=parse({'<original>':original,**sources},package,occurrence_bindings=True)
 leaves=original_leaves(parsed['<original>']['declarations'],split_names(rows))
 lookup=all_nodes(parsed);files=set()
 for row in rows:
  owner,_,name=row['original_name'].rpartition('.')
  target=(row['destination_file'],row['destination_class'],row['new_name'])
  old=(config['source'],owner,name or row['original_name'])
  for key in {old,target}:
   if key in lookup:files.add(key[0])
 files.update(p for p in config['scaffold_file_steps'] if p in sources)
 return {'source':original,'members':{name:node['text'] for name,node in leaves.items()},'files':sorted(files)}

def read_validated_source(path, package):
 config=json.loads((ROOT/'dev/tool/iptv_spotlight_timeline_checker_config.json').read_text())
 if path!=config['source']:raise ValueError('Unregistered auxiliary timeline source: '+path)
 rows=list(csv.DictReader((ROOT/'dev/tool/iptv_spotlight_timeline_manifest.tsv').open(),delimiter='\t'))
 original=subprocess.check_output(['git','show',config['baseline']+':'+path],cwd=ROOT,text=True)
 sources={path:(ROOT/path).read_text(),**{p.relative_to(ROOT).as_posix():p.read_text() for p in (ROOT/config['feature']).rglob('*.dart')}}
 return validate(original,sources,rows,config,package)['source']

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--parser-package',type=Path,required=True);p.add_argument('--json',action='store_true');args=p.parse_args()
 package=args.parser_package.resolve();ensure_parser_package(package.parent.parent,package)
 config=json.loads((ROOT/'dev/tool/iptv_spotlight_timeline_checker_config.json').read_text())
 rows=list(csv.DictReader((ROOT/'dev/tool/iptv_spotlight_timeline_manifest.tsv').open(),delimiter='\t'))
 original=subprocess.check_output(['git','show',config['baseline']+':'+config['source']],cwd=ROOT,text=True)
 sources={config['source']:(ROOT/config['source']).read_text(),**{p.relative_to(ROOT).as_posix():p.read_text() for p in (ROOT/config['feature']).rglob('*.dart')}}
 result=validate(original,sources,rows,config,package)
 print(json.dumps(result) if args.json else result['source'])
if __name__=='__main__':main()
