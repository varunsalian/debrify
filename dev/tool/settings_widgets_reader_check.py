#!/usr/bin/env python3
"""Cross-check the frozen Dart reader against all analyzer spans and negatives."""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path
from check_verbatim_moves import parse
from settings_widgets_probe import SOURCE, FEATURE

ROOT = Path(__file__).resolve().parents[2]
ORIGINAL_SUBJECT = 'test(settings-widgets): step 0b close review gaps on original'

def original_revision(rev):
    if rev is None:
        # Consume the complete log; an early-exiting pipe can fail under pipefail.
        log=subprocess.check_output(['git','log','--format=%H%x09%s'],cwd=ROOT,text=True)
        matches=[line.split('\t',1)[0] for line in log.splitlines() if line.split('\t',1)[1]==ORIGINAL_SUBJECT]
        if len(matches)!=1:
            raise ValueError(f'Expected one checkpoint with exact subject {ORIGINAL_SUBJECT!r}; found {len(matches)}')
        rev=matches[0]
    return subprocess.check_output(['git','rev-parse','--verify',rev+'^{commit}'],cwd=ROOT,text=True).strip()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--rev',help='Original revision (default: exact step 0b checkpoint subject)')
    p.add_argument('--parser-package',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args()
    rev=original_revision(args.rev)
    source=subprocess.check_output(['git','show',rev+':'+SOURCE],cwd=ROOT,text=True)
    package=args.parser_package.resolve()
    kernel=package.parent/'settings_widgets_reader.dill'
    kernel.parent.mkdir(parents=True,exist_ok=True)
    subprocess.run(['dart','compile','kernel','--packages='+str(package),'-o',str(kernel),str(ROOT/'test/support/settings_widgets_source.dart')],cwd=ROOT,check=True,stdout=subprocess.DEVNULL)
    ast=parse({'original':source},package)['original']
    scratch_base=ROOT/'.dart_tool/settings_widgets/reader-fixtures';scratch_base.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(dir=scratch_base) as tmp:
        root=Path(tmp);original=root/SOURCE;original.parent.mkdir(parents=True)
        original.write_text(source)
        spans=json.loads(subprocess.check_output(['dart',str(kernel),'spans',str(original)],text=True))
        expected=[{k:n[k] for k in ('name','start','end')} for n in ast['declarations']]
        assert spans==expected, [(a,b) for a,b in zip(expected,spans) if a!=b]
        assert len(spans)==60
        rows={r['original_name']:r for r in __import__('check_verbatim_moves').read_manifest(ROOT/'dev/tool/settings_widgets_manifest.tsv')}
        kinds={}
        for node in ast['declarations']:
            kinds.setdefault(node['kind'],node)
        results=[]
        for kind,node in kinds.items():
            original.write_text(source[:node['start']]+source[node['end']:])
            result=subprocess.run(['dart',str(kernel),'read',str(root),node['name']],capture_output=True,text=True,cwd=ROOT)
            assert result.returncode and 'has 0 physical declarations' in result.stderr, result.stderr
            results.append({'kind':kind,'name':node['name'],'deletion':'rejected'})
            original.write_text(source)
            destination=root/rows[node['name']]['destination_file'];destination.parent.mkdir(parents=True,exist_ok=True);destination.write_text(node['text']+'\n')
            result=subprocess.run(['dart',str(kernel),'read',str(root),node['name']],capture_output=True,text=True,cwd=ROOT)
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
    args.output.write_text(json.dumps({'revision':rev,'spans':spans,'all_60_exact':True,'per_kind_negatives':results,'lexical_fixture':'passed'},indent=2)+'\n')
    print('Reader: 60 exact analyzer spans; deletion/duplication for 4 kinds; lexical stress fixture PASS')
if __name__=='__main__': main()
