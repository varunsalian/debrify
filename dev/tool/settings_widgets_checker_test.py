"""Real configuration positives and move-only negative fixtures."""
import csv
import json
import subprocess
from pathlib import Path
from settings_widgets_probe import split_sources, SOURCE

def self_test(package=None):
    from check_settings_moves import ROOT,check
    from check_verbatim_moves import parse
    config=json.loads((ROOT/'dev/tool/settings_widgets_checker_config.json').read_text())
    overlay=json.loads((ROOT/'dev/tool/settings_widgets_verbatim_fixtures/config.json').read_text())
    assert set(overlay)=={'source','feature'}
    assert overlay['source']==config['source'] and overlay['feature']==config['feature']
    config.update(overlay)
    rows=list(csv.DictReader((ROOT/'dev/tool/settings_widgets_manifest.tsv').open(),delimiter='\t'))
    original=subprocess.check_output(['git','show',config['baseline']+':'+SOURCE],cwd=ROOT,text=True)
    current={SOURCE:(ROOT/SOURCE).read_text()}
    current.update({p.relative_to(ROOT).as_posix():p.read_text() for p in (ROOT/config['feature']).rglob('*.dart')})
    assert not check(original,current,rows,SOURCE,package,config=config)
    parsed=parse({'original':original},package)['original']
    complete=split_sources(original,parsed)
    assert not check(original,complete,rows,SOURCE,package,config=config)
    print('settings_widgets real-config original/current and complete split: PASS')
    for case in json.loads((ROOT/'dev/tool/settings_widgets_verbatim_fixtures/cases.json').read_text()):
        path=next(r['destination_file'] for r in rows if r['original_name']==case['member'])
        changed=dict(complete);text=changed[path];assert case['before'] in text,case['name']
        changed[path]=text.replace(case['before'],case['after'],1)
        assert changed[path]!=text
        assert check(original,changed,rows,SOURCE,package,config=config),case['name']
        print('settings_widgets '+case['name']+': rejected')
    name='WebDavSyncPendingBadge';row=next(r for r in rows if r['original_name']==name)
    node=next(n for n in parsed['declarations'] if n['name']==name)
    changed=dict(complete);changed[rows[0]['destination_file']]+='\n'+node['text']+'\n'
    assert check(original,changed,rows,SOURCE,package,config=config)
    print('settings_widgets duplicate physical declaration: rejected')
    changed=dict(complete);changed[row['destination_file']]=changed[row['destination_file']].replace(node['text'],'')
    assert check(original,changed,rows,SOURCE,package,config=config)
    print('settings_widgets missing manifest leaf: rejected')
