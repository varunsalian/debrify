#!/usr/bin/env python3
"""Premiumize feature guards through real main, including the unregistered peer."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FEATURE = 'lib/features/premiumize_files/'


def main():
    from check_search_architecture import (
        FEATURES, PREMIUMIZE_COMPLETE, PREMIUMIZE_FACADE,
        PREMIUMIZE_FACADE_CAP, PREMIUMIZE_BRIDGE,
    )
    peer_registered = "alldebrid_files" in FEATURES
    with tempfile.TemporaryDirectory(prefix='premiumize_architecture_', dir=ROOT / '.dart_tool') as directory:
        tree = Path(directory)
        shutil.copytree(ROOT / 'lib', tree / 'lib')
        tool = tree / 'dev/tool/check_search_architecture.py'
        tool.parent.mkdir(parents=True)
        shutil.copy2(ROOT / 'dev/tool/check_search_architecture.py', tool)
        def run():
            return subprocess.run(['python3', str(tool)], cwd=tree, text=True, capture_output=True)
        positive = run()
        assert positive.returncode == 0, positive.stderr
        results = {'original_tree': 'PASS'}
        probe = tree / (FEATURE + 'application/premiumize_guard_probe.dart')
        cases = [
            ('facade import', "import 'package:debrify/screens/premiumize/premiumize_files_screen.dart';\n", 'imports the files facade'),
            ('legacy service in application', "import 'package:debrify/services/premiumize_service.dart';\n", 'Premiumize application'),
            ('BuildContext in application', 'BuildContext? context;\n', 'references BuildContext'),
            ('HTTP in application', "import 'package:http/http.dart';\n", 'imports a data implementation'),
            ('500 line destination cap', '// probe\n' * 501, '500-line Premiumize extraction'),
            ('late field', 'class Probe { late int value; }\n', 'late initialization'),
        ]
        for peer in ('pikpak_files', 'torbox_downloads', 'debrid_downloads', 'alldebrid_files'):
            cases.append((peer + ' forward import', "import 'package:debrify/features/" + peer + "/models/probe.dart';\n", 'Premiumize/cloud feature cross-import'))
        for name, source, expected in cases:
            probe.write_text(source)
            result = run()
            assert result.returncode != 0 and expected in result.stderr, (name, result.stderr)
            results[name] = 'rejected by real main'
        probe.unlink()
        for peer in ('pikpak_files', 'torbox_downloads', 'debrid_downloads', 'alldebrid_files'):
            peer_probe = tree / ('lib/features/' + peer + '/application/premiumize_reverse_probe.dart')
            peer_probe.parent.mkdir(parents=True, exist_ok=True)
            peer_probe.write_text("import 'package:debrify/features/premiumize_files/models/premiumize_view.dart';\n")
            result = run()
            assert result.returncode != 0 and 'Premiumize/cloud feature cross-import' in result.stderr, (peer, result.stderr)
            results[peer + ' reverse import'] = 'rejected by real main'
            if peer == 'alldebrid_files':
                original = tool.read_text()
                tool.write_text(original.replace('FEATURES += ("premiumize_files",)', 'FEATURES += ("premiumize_files", "alldebrid_files")'))
                result = run()
                assert result.returncode != 0 and 'Premiumize/cloud feature cross-import' in result.stderr, result.stderr
                results['registered AllDebrid reverse import'] = 'rejected by real main'
                tool.write_text(original)
                peer_probe.write_text('class UnrelatedPeer { late int value; }\n' + '// unrelated peer\n' * 801)
                result = run()
                if peer_registered:
                    assert result.returncode != 0 and '800-line ceiling' in result.stderr, result.stderr
                    results['registered peer existing guards retained'] = 'rejected by real main'
                else:
                    assert result.returncode == 0, 'Unregistered peer scan must stay restricted to Premiumize cross-imports'
                    results['unregistered peer unrelated violations ignored'] = 'PASS'
            peer_probe.unlink()
        if PREMIUMIZE_COMPLETE:
            facade = tree / PREMIUMIZE_FACADE
            original_facade = facade.read_text()
            lines = len(original_facade.splitlines())
            assert lines <= PREMIUMIZE_FACADE_CAP
            facade.write_text(original_facade + '\n' * (PREMIUMIZE_FACADE_CAP - lines + 1))
            result = run()
            assert result.returncode != 0 and 'Premiumize facade limit' in result.stderr, result.stderr
            results['measured facade cap'] = 'rejected by real main'
            facade.write_text(original_facade)
            changed = original_facade.replace('\n\n', '\n// TEMP(premiumize) probe\n', 1)
            assert changed != original_facade and len(changed.splitlines()) == lines
            facade.write_text(changed)
            result = run()
            assert result.returncode != 0 and 'temporary Premiumize cross-call remains in the facade' in result.stderr, result.stderr
            results['completed facade temporary marker'] = 'rejected by real main'
            facade.write_text(original_facade)
            bridge_probe = tree / (PREMIUMIZE_BRIDGE + 'premiumize_completion_probe.dart')
            bridge_probe.write_text('// TEMP(premiumize) probe\n')
            result = run()
            assert result.returncode != 0 and 'temporary Premiumize cross-call' in result.stderr, result.stderr
            results['completed legacy bridge temporary marker'] = 'rejected by real main'
            bridge_probe.unlink()
        assert run().returncode == 0
        print(json.dumps(results, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
