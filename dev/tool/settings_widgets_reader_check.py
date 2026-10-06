#!/usr/bin/env python3
"""Cross-check the frozen Dart reader against all analyzer spans and negatives."""
import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
from check_verbatim_moves import parse
from settings_widgets_probe import SOURCE, FEATURE

ROOT = Path(__file__).resolve().parents[2]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--parser-package',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args()
    package=args.parser_package.resolve()
    kernel=package.parent/'settings_widgets_reader.dill'
    subprocess.run(['dart','compile','kernel','--packages='+str(package),'-o',str(kernel),'test/support/settings_widgets_source.dart'],check=True,stdout=subprocess.DEVNULL)
    source=Path(SOURCE).read_text()
    ast=parse({'original':source},package)['original']
    spans=json.loads(subprocess.check_output(['dart',str(kernel),'spans',SOURCE],text=True))
    expected=[{k:n[k] for k in ('name','start','end')} for n in ast['declarations']]
    assert spans==expected, [(a,b) for a,b in zip(expected,spans) if a!=b]
    assert len(spans)==60
    rows={r['original_name']:r for r in __import__('check_verbatim_moves').read_manifest('dev/tool/settings_widgets_manifest.tsv')}
    kinds={}
    for node in ast['declarations']:
        kinds.setdefault(node['kind'],node)
    results=[]
    scratch_base=Path('.dart_tool/settings_widgets/reader-fixtures');scratch_base.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(dir=scratch_base) as tmp:
        root=Path(tmp);original=root/SOURCE;original.parent.mkdir(parents=True)
        for kind,node in kinds.items():
            original.write_text(source[:node['start']]+source[node['end']:])
            result=subprocess.run(['dart',str(kernel),'read',str(root),node['name']],capture_output=True,text=True)
            assert result.returncode and 'has 0 physical declarations' in result.stderr, result.stderr
            results.append({'kind':kind,'name':node['name'],'deletion':'rejected'})
            original.write_text(source)
            destination=root/rows[node['name']]['destination_file'];destination.parent.mkdir(parents=True,exist_ok=True);destination.write_text(node['text']+'\n')
            result=subprocess.run(['dart',str(kernel),'read',str(root),node['name']],capture_output=True,text=True)
            assert result.returncode and 'has 2 physical declarations' in result.stderr,result.stderr
            results[-1]['duplication']='rejected';destination.unlink()
        # Stress lexical boundaries beyond the original: nested comments,
        # raw/triple strings, interpolation with quoted braces and generics.
        fixture=root/'lexical.dart'
        fixture.write_text('''/// docs { ; }
abstract final class Lexical { static const raw = r"};"; }
/* outer /* nested */ end */
final List<String> literals = [r"};", "${{'key': "}"}}", """};"""];
T identity<T>(T value) { return value; }
bool predicate(int value) => value > 0;
String? memo;
enum Example { a, b }
''')
        actual=json.loads(subprocess.check_output(['dart',str(kernel),'spans',str(fixture)],text=True))
        fixture_ast=parse({'fixture':fixture.read_text()},package)['fixture']
        assert actual==[{k:n[k] for k in ('name','start','end')} for n in fixture_ast['declarations']]
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps({'spans':spans,'all_60_exact':True,'per_kind_negatives':results,'lexical_fixture':'passed'},indent=2)+'\n')
    print('Reader: 60 exact analyzer spans; deletion/duplication for 4 kinds; lexical stress fixture PASS')
if __name__=='__main__': main()
