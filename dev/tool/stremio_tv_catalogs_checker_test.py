"""Real staged config: ORIGINAL/complete positives and move-contract negatives."""
import copy
import csv
import json
import subprocess
from pathlib import Path


def self_test(package=None):
    from check_settings_moves import ROOT, check
    from check_verbatim_moves import parse
    from stremio_tv_catalogs_probe import SOURCE, BRIDGE, active_config, split_sources
    assert package is not None, 'An isolated --parser-package is required'
    config=json.loads((ROOT/'dev/tool/stremio_tv_catalogs_checker_config.json').read_text())
    rows=list(csv.DictReader((ROOT/'dev/tool/stremio_tv_catalogs_manifest.tsv').open(),delimiter='\t'))
    original=subprocess.check_output(['git','show',config['baseline']+':'+SOURCE],cwd=ROOT,text=True)
    def verify(sources, cfg=config):
        return check(original,sources,rows,SOURCE,package,config=cfg)
    assert not verify({SOURCE:original}), verify({SOURCE:original})
    print('Stremio catalogs ORIGINAL positive: PASS')
    complete=split_sources(original,parse({SOURCE:original},package)[SOURCE]); active=active_config(config)
    errors=verify(complete,active); assert not errors, errors
    print('Stremio catalogs complete split positive: PASS')
    assert verify({SOURCE:original},active), 'Ahead-of-owner registration accepted'
    unowned=copy.deepcopy(active);unowned['additional_owners']=[]
    errors=verify(complete,unowned)
    assert sum('Unregistered settings destination owner' in e for e in errors)==5,errors
    print('Staged alias registrations / five additional owners: PASS')
    url=BRIDGE+'local_catalog_url_import_dialog.dart'
    trakt=BRIDGE+'local_catalog_trakt_import_dialog.dart'
    editor=BRIDGE+'local_catalog_editor_dialog.dart'
    cases=[
      ('changed alias target',url,'typedef LcUrlDialog = _ImportUrlDialog;','typedef LcUrlDialog = _ImportJsonDialog;'),
      ('changed value alias target',url,'const lcBackHop = _backHopsTo;','const lcBackHop = isActivateKey;'),
      ('owner-local value alias use',url,'          _backHopsTo(', '          lcBackHop('),
      ('external private spelling',BRIDGE+'local_catalog_json_import_dialog.dart','          lcBackHop(', '          _backHopsTo('),
      ('owner-local alias use',url,'State<_ImportUrlDialog> createState()', 'State<LcUrlDialog> createState()'),
      ('renamed private class',url,'class _ImportUrlDialog extends','class RenamedImportUrlDialog extends'),
      ('reworded section comment',url,'Import from URL dialog','Import URL content'),
      ('dispose order',url,'_nameFocusNode.dispose();\n    _urlFocusNode.dispose();','_urlFocusNode.dispose();\n    _nameFocusNode.dispose();'),
      ('focus label',url,"'stremio-import-url-name'","'changed-label'"),
      ('timeout',url,'Duration(seconds: 15)','Duration(seconds: 30)'),
      ('extension target',trakt,'extension _TraktListSourceExt on _TraktListSource','extension _TraktListSourceExt on _MdblistListCategory'),
      ('extension renamed',trakt,'extension _TraktListSourceExt on','extension _RenamedTraktExt on'),
      ('extension generic header',trakt,'extension _TraktListSourceExt on','extension _TraktListSourceExt<T> on'),
      ('extension member body',trakt,"return 'Watchlist';","return 'Changed';"),
    ]
    for label,file,before,after in cases:
        assert complete[file].count(before)==(2 if label=='owner-local value alias use' else 1),(label,before)
        changed=dict(complete);changed[file]=changed[file].replace(before,after,1)
        if label == 'renamed private class':
            changed[file]=changed[file].replace('const _ImportUrlDialog();','const RenamedImportUrlDialog();')
        errors=verify(changed,active);assert errors,'Accepted '+label
        if label=='extension generic header':
            assert any('header changed: _TraktListSourceExt' in e for e in errors),errors
        print('Stremio catalogs negative '+label+': rejected')
    node=next(n for n in parse({SOURCE:original},package)[SOURCE]['declarations'] if n['name']=='_TraktListSourceExt')
    duplicate=dict(complete);duplicate[editor]+='\n'+node['text']+'\n'
    assert verify(duplicate,active),'Accepted duplicate extension'
    missing=dict(complete);missing[trakt]=missing[trakt].replace(node['text'],'')
    assert verify(missing,active),'Accepted missing extension'
    for label,header in [('extension type','extension type _TraktListSourceExt(int value) on _TraktListSource'),('extension implements','extension _TraktListSourceExt on _TraktListSource implements Object')]:
        changed=dict(complete);changed[trakt]=changed[trakt].replace('extension _TraktListSourceExt on _TraktListSource',header)
        try: errors=verify(changed,active)
        except (subprocess.CalledProcessError,ValueError): errors=['parser rejected']
        assert errors,'Accepted '+label
        print('Stremio catalogs negative '+label+': rejected')
    print('Stremio catalogs extension duplicate / missing: rejected')
