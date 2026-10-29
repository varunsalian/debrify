#!/usr/bin/env python3
"""settings_widgets guard proofs through the real main on an owned tree copy."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FACADE = 'lib/screens/settings/widgets/settings_widgets.dart'
FEATURE = 'lib/features/settings_widgets/presentation/'


def main():
    scratch=ROOT / '.dart_tool'
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='settings_widgets_architecture_', dir=scratch) as directory:
        tree = Path(directory)
        shutil.copytree(ROOT / 'lib', tree / 'lib')
        tool = tree / 'dev/tool/check_search_architecture.py'
        tool.parent.mkdir(parents=True)
        shutil.copy2(ROOT / 'dev/tool/check_search_architecture.py', tool)
        complete = 'SETTINGS_WIDGETS_COMPLETE = True' in tool.read_text()

        def run():
            return subprocess.run(['python3', str(tool)], cwd=tree, text=True, capture_output=True)

        positive = run()
        assert positive.returncode == 0, positive.stderr
        results = {'unmodified_tree': 'PASS'}
        token = FEATURE + 'settings_tokens.dart'
        cases = [
            ('facade back import', token, "import 'package:debrify/screens/settings/widgets/settings_widgets.dart';\n", 'imports its facade'),
            ('screen import', token, "import 'package:debrify/screens/settings_screen.dart';\n", 'imports a screen'),
            ('URL launcher outside links', token, "import 'package:url_launcher/url_launcher.dart';\n", 'outside its links'),
            ('unregistered service', token, "import 'package:debrify/services/main_page_bridge.dart' show MainPageBridge;\n", 'outside its exact'),
            ('HTTP import', token, "import 'package:http/http.dart';\n", 'playback/storage/http'),
            ('preferences import', token, "import 'package:shared_preferences/shared_preferences.dart';\n", 'playback/storage/http'),
            ('database import', token, "import 'package:sqflite/sqflite.dart';\n", 'playback/storage/http'),
            ('playback import', token, "import 'package:media_kit/media_kit.dart';\n", 'playback/storage/http'),
            ('launcher import', token, "import 'package:debrify/services/video_player_launcher.dart';\n", 'playback/storage/http'),
            ('temporary marker', token, '// TEMP(settings_widgets) negative\n', 'temporary settings widgets'),
            ('feature over cap', token, '// settings_widgets measured cap negative\n' * 501, '500-line settings widgets'),
        ]
        for peer, relative in [
            ('settings', 'lib/features/settings/presentation/settings_connection_grid.dart'),
            ('playback_settings', 'lib/features/playback_settings/presentation/playback_settings_view.dart'),
            ('iptv_settings', 'lib/features/iptv_settings/presentation/iptv_settings_view.dart'),
        ]:
            # Use an existing registered feature file, independent of its filename.
            relative = next((tree / 'lib/features' / peer).rglob('*.dart')).relative_to(tree).as_posix()
            cases.append((peer + ' forward import', token, f"import 'package:debrify/features/{peer}/presentation/settings_widgets_guard_fixture.dart';\n", 'settings-family implementation'))
            cases.append((peer + ' reverse import', relative, "import 'package:debrify/features/settings_widgets/presentation/settings_tokens.dart';\n", 'settings-family implementation'))
        for name, filename, prefix, expected in cases:
            path = tree / filename
            original = path.read_text()
            try:
                path.write_text(prefix + original)
                result = run()
                assert result.returncode != 0 and expected in result.stderr, (name, result.stderr)
                results[name] = 'rejected by real main'
            finally:
                path.write_text(original)
        # Both exact service pairs are independently proven before their move.
        for filename, target, name in [
            ('settings_connection_card.dart', 'services/main_page_bridge.dart', 'MainPageBridge'),
            ('settings_legacy_mode_dialog.dart', 'services/profiles/profile_bootstrap.dart', 'ProfileBootstrap'),
        ]:
            path = tree / FEATURE / filename
            existed = path.exists()
            original = path.read_text() if existed else ''
            try:
                path.write_text(f"import 'package:debrify/{target}' show {name};\n")
                result = run()
                assert result.returncode == 0, result.stderr
                results[name + ' exact show'] = 'PASS'
                for kind, directive in [('unshown', ';'), ('over-shown', f' show {name}, Extra;'), ('wrong name', ' show Extra;')]:
                    path.write_text(f"import 'package:debrify/{target}'{directive}\n")
                    result = run()
                    assert result.returncode != 0 and 'show only allowed declarations' in result.stderr, result.stderr
                    results[name + ' ' + kind] = 'rejected by real main'
            finally:
                if existed:
                    path.write_text(original)
                else:
                    path.unlink()
        # Family model contracts remain permitted in both directions.
        for peer in ['settings', 'playback_settings', 'iptv_settings']:
            path = tree / 'lib/features' / peer / 'models/settings_widgets_guard_fixture.dart'
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("export 'package:debrify/features/settings_widgets/models/settings_widgets_guard_fixture.dart';\n")
            tokens = tree / token
            original = tokens.read_text()
            try:
                tokens.write_text(f"import 'package:debrify/features/{peer}/models/settings_widgets_guard_fixture.dart';\n" + original)
                result = run()
                assert result.returncode == 0, result.stderr
                results[peer + ' model contracts both ways'] = 'PASS'
            finally:
                tokens.write_text(original)
                path.unlink()
        if complete:
            path = tree / FACADE
            original = path.read_text()
            cases = [
                ('missing facade', None, 'missing'),
                ('facade declaration', original + '\nclass ExtraSettingsWidgets {}\n', 'only export'),
                ('facade import', "import 'package:flutter/material.dart';\n" + original, 'only export'),
                ('facade over cap', original + '// settings_widgets facade cap negative\n' * 501, 'facade limit'),
                ('missing exported name', original.replace('kSettingsAccent,', ''), 'original 47 names'),
                ('wrong export target', original.replace('features/settings_widgets/presentation/', 'features/settings/presentation/', 1), 'feature destinations'),
                ('facade temporary marker', original + '// TEMP(settings_widgets) negative\n', 'temporary settings widgets'),
            ]
            for name, changed, expected in cases:
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
                    path.write_text(original)
        assert run().returncode == 0
        print(json.dumps(results, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
