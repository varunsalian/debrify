#!/usr/bin/env python3
"""Two-pane guard proofs through the shared checker's real main, in an owned copy."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FACADE = 'lib/screens/settings/iptv_settings_two_pane.dart'
FEATURE = 'lib/features/iptv_settings_two_pane/presentation/'
BRIDGE = FEATURE + 'legacy_iptv_settings_two_pane/'


def main():
    scratch = ROOT / '.dart_tool'
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='iptv_settings_two_pane_architecture_', dir=scratch) as directory:
        tree = Path(directory)
        shutil.copytree(ROOT / 'lib', tree / 'lib')
        tool = tree / 'dev/tool/check_search_architecture.py'
        tool.parent.mkdir(parents=True)
        shutil.copy2(ROOT / 'dev/tool/check_search_architecture.py', tool)
        spec = importlib.util.spec_from_file_location('two_pane_guard_fixture', tool)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        complete = module.IPTV_SETTINGS_TWO_PANE_COMPLETE
        results = {}

        def run():
            return subprocess.run(['python3', str(tool)], cwd=tree, text=True, capture_output=True)

        def positive(name):
            result = run()
            assert result.returncode == 0, (name, result.stderr)
            results[name] = 'PASS'

        def negative(name, filename, changed, expected):
            path = tree / filename
            existed = path.exists()
            original = path.read_text() if existed else ''
            path.parent.mkdir(parents=True, exist_ok=True)
            try:
                if changed is None:
                    path.unlink()
                else:
                    assert changed != original, 'No-op negative: ' + name
                    path.write_text(changed)
                result = run()
                assert result.returncode != 0 and expected in result.stderr, (name, result.stderr)
                results[name] = 'rejected by real main'
            finally:
                if existed:
                    path.write_text(original)
                elif path.exists():
                    path.unlink()

        positive('unmodified tree')
        token = FEATURE + 'iptv_two_pane_destination.dart'
        original = (tree / token).read_text()
        cases = [
            ('facade back import', "import 'package:debrify/screens/settings/iptv_settings_two_pane.dart';\n", 'imports its facade'),
            ('service outside bridge', "import 'package:debrify/services/iptv_source_stats.dart' show IptvSourceStats;\n", 'outside its legacy bridge'),
            ('screen outside bridge', "import 'package:debrify/screens/settings/iptv_style_page.dart' show iptvStyleLabel;\n", 'outside its legacy bridge'),
            ('HTTP', "import 'package:http/http.dart';\n", 'playback/storage/http/native/profile'),
            ('preferences', "import 'package:shared_preferences/shared_preferences.dart';\n", 'playback/storage/http/native/profile'),
            ('database', "import 'package:sqflite/sqflite.dart';\n", 'playback/storage/http/native/profile'),
            ('player', "import 'package:media_kit/media_kit.dart';\n", 'playback/storage/http/native/profile'),
            ('launcher', "import 'package:debrify/services/video_player_launcher.dart';\n", 'playback/storage/http/native/profile'),
            ('player launch', "import 'package:debrify/features/player_launch/presentation/player_launch.dart';\n", 'playback/storage/http/native/profile'),
            ('native bridge', "import 'package:debrify/services/native_bridge.dart';\n", 'playback/storage/http/native/profile'),
            ('profile', "import 'package:debrify/services/profiles/profile_bootstrap.dart';\n", 'playback/storage/http/native/profile'),
            ('temporary marker', '// TEMP(iptv_settings_two_pane) negative\n', 'temporary IPTV settings two-pane'),
            ('Builder wrapper', 'final guard = Builder(builder: (_) => null);\n', 'wrapper or keep-alive'),
            ('KeepAlive wrapper', 'final guard = KeepAlive(child: null);\n', 'wrapper or keep-alive'),
            ('IndexedStack wrapper', 'final guard = IndexedStack();\n', 'wrapper or keep-alive'),
            ('feature cap', '// negative cap\n' * 501, '500-line IPTV settings two-pane'),
        ]
        for name, prefix, expected in cases:
            negative(name, token, prefix + original, expected)
        bridge_token = BRIDGE + 'iptv_settings_two_pane_dependencies.dart'
        negative('bridge cap', bridge_token, '// negative cap\n' * 501, '500-line IPTV settings two-pane')
        negative('unregistered bridge service', bridge_token,
                 "import 'package:debrify/services/iptv_source_stats.dart' show IptvSourceStats;\n",
                 'outside its exact per-file registration')
        negative('unregistered bridge screen', bridge_token,
                 "import 'package:debrify/screens/settings/iptv_style_page.dart' show iptvStyleLabel;\n",
                 'outside its exact per-file registration')
        # Every destination/URI pair is exact, including the two disjoint style lists.
        for filename, imports in module.PRESENTATION_BRIDGE_IMPORTS.items():
            if not filename.startswith(BRIDGE):
                continue
            path = tree / filename
            existed = path.exists()
            saved = path.read_text() if existed else ''
            path.parent.mkdir(parents=True, exist_ok=True)
            try:
                for target, names in imports.items():
                    uri = 'package:debrify/' + target[4:]
                    shown = ', '.join(sorted(names))
                    path.write_text(f"import '{uri}' show {shown};\n")
                    label = path.name + ':' + target
                    positive(label + ' exact show')
                    for kind, directive in [('unshown', ';'), ('over-shown', f' show {shown}, Extra;'),
                                            ('wrong name', ' show Extra;'), ('duplicate name', f' show {shown}, {sorted(names)[0]};')]:
                        negative(label + ' ' + kind, filename, f"import '{uri}'{directive}\n",
                                 'exact per-file registered declarations')
            finally:
                if existed:
                    path.write_text(saved)
                else:
                    path.unlink()
        for peer in ['settings', 'iptv', 'iptv_settings', 'settings_widgets']:
            peer_file = next((tree / 'lib/features' / peer).rglob('*.dart')).relative_to(tree).as_posix()
            negative(peer + ' forward', token,
                     f"import 'package:debrify/features/{peer}/presentation/guard.dart';\n" + original,
                     'settings-family implementation')
            negative(peer + ' reverse', peer_file,
                     "import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_destination.dart';\n" + (tree / peer_file).read_text(),
                     'settings-family implementation')
            model = tree / 'lib/features' / peer / 'models/two_pane_guard_fixture.dart'
            model.parent.mkdir(parents=True, exist_ok=True)
            model.write_text("export 'package:debrify/features/iptv_settings_two_pane/models/two_pane_guard_fixture.dart';\n")
            try:
                (tree / token).write_text(f"import 'package:debrify/features/{peer}/models/two_pane_guard_fixture.dart';\n" + original)
                positive(peer + ' model contracts both ways')
            finally:
                (tree / token).write_text(original)
                model.unlink()
        # Exercise unconditional scanning with completion disabled, even at step 3.
        tool_original = tool.read_text()
        try:
            tool.write_text(tool_original.replace('IPTV_SETTINGS_TWO_PANE_COMPLETE = True', 'IPTV_SETTINGS_TWO_PANE_COMPLETE = False'))
            negative('incomplete feature scanned', token, '// negative cap\n' * 501, '500-line IPTV settings two-pane')
            positive('incomplete feature positive')
        finally:
            tool.write_text(tool_original)
        if complete:
            facade = (tree / FACADE).read_text()
            for name, changed, expected in [
                ('missing facade', None, 'missing'),
                ('facade declaration', facade + 'class Extra {}\n', 'only export'),
                ('facade import', "import 'package:flutter/material.dart';\n" + facade, 'only export'),
                ('facade cap', facade + '// negative cap\n', 'facade limit'),
                ('missing export', facade.replace('IptvAutoRefreshDialog, ', ''), 'original five names'),
                ('extra export', facade.replace('IptvAutoRefreshDialog, ', 'Extra, IptvAutoRefreshDialog, '), 'original five names'),
                ('wrong destination', facade.replace('iptv_auto_refresh_dialog.dart', 'iptv_two_pane_destination.dart'), 'exact destination'),
                ('swapped destinations', facade.replace('IptvAutoRefreshDialog, ', 'IptvSettingsTwoPane, ').replace('show IptvSettingsTwoPane, IptvSettingsTwoPaneState', 'show IptvAutoRefreshDialog, IptvSettingsTwoPaneState'), 'exact destination'),
                ('facade marker', facade + '// TEMP(iptv_settings_two_pane) negative\n', 'temporary IPTV settings two-pane'),
            ]:
                negative(name, FACADE, changed, expected)
        positive('restored tree')
        print(json.dumps(results, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
