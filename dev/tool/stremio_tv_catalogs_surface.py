"""Resolve the actual exported library namespace with an isolated analyzer."""
import argparse
import json
import subprocess
from pathlib import Path
from check_verbatim_moves import ROOT, ensure_parser_package, parser_lock

if __name__ == '__main__':
    p=argparse.ArgumentParser();p.add_argument('--parser-package',type=Path,required=True);p.add_argument('--source',required=True);a=p.parse_args()
    package=a.parser_package.resolve();assert package.is_relative_to(ROOT/'.dart_tool')
    ensure_parser_package(package.parent.parent,package)
    adapter=ROOT/'dev/tool/stremio_tv_catalogs_surface.dart.txt';kernel=package.parent/'stremio_tv_catalogs_surface.dill'
    with parser_lock(package.parent):
        if not kernel.exists() or kernel.stat().st_mtime<adapter.stat().st_mtime:
            subprocess.run(['dart','compile','kernel','--packages='+str(package),'-o',str(kernel),str(adapter)],stdout=subprocess.DEVNULL,check=True)
    result=subprocess.run(['dart',str(kernel),str((ROOT/a.source).resolve())],capture_output=True,text=True,check=True)
    names=json.loads(result.stdout);assert isinstance(names,list);print(json.dumps(names))
