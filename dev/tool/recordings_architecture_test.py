#!/usr/bin/env python3
"""Real recordings guard probes on an owned source-tree copy, at every step."""
import ast
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import tempfile


def main():
    root = Path(__file__).resolve().parents[2]
    spec = importlib.util.spec_from_file_location(
        'recordings_architecture', root / 'dev/tool/check_search_architecture.py')
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    with tempfile.TemporaryDirectory(prefix='recordings_architecture_', dir=root / '.dart_tool') as directory:
        copy = Path(directory)
        shutil.copytree(root / 'lib', copy / 'lib')
        checker.ROOT = copy
        base = 'lib/features/recordings/'
        bridge = checker.RECORDINGS_BRIDGE
        facade = checker.RECORDINGS_FACADE
        results = {}
        completed_tree = json.loads((root / 'dev/tool/recordings_checker_config.json').read_text())['completed_step'] >= 4
        assert checker.RECORDINGS_COMPLETE == completed_tree
        if completed_tree:
            assert facade in checker.COMPOSITION_ROOTS
            assert checker.RECORDINGS_SIZE_EXCEPTIONS == {}
            assert len((copy / facade).read_text().splitlines()) == checker.RECORDINGS_FACADE_CAP <= 150
            results['real completed facade cap and composition root'] = 'PASS'
        # Reuse the real ink scanner without its unconditional CLI entrypoint.
        module = ast.parse((root / 'dev/tool/light_ink_inventory.py').read_text())
        module.body = module.body[:-1]
        ink = {'__file__': str(root / 'dev/tool/light_ink_inventory.py')}
        exec(compile(module, 'light_ink_inventory.py', 'exec'), ink)
        ink['REPO'] = str(copy)
        wrapped = "color: _focused\n    ? kRecordingsHubGold\n    : Colors.white.withValues(alpha: 0.06),\n"
        ink_file = copy / (base + 'presentation/ink_probe.dart')
        ink_file.write_text(wrapped)
        try:
            assert ink['scan'](ink_file.relative_to(copy).as_posix()) == [
                (3, 'color: _focused ? kRecordingsHubGold : Colors.white.withValues(alpha: 0.06),')]
            # The opt-in must not broaden any other feature's lexical scan.
            assert ink['scan'](str(ink_file)) == []
            ink_file.write_text(wrapped.replace('color:', 'fill:'))
            assert ink['scan'](ink_file.relative_to(copy).as_posix()) == []
            ink_file.write_text(wrapped.replace('kRecordingsHubGold', 'Colors.white'))
            assert ink['scan'](ink_file.relative_to(copy).as_posix()) == []
            ink_file.write_text(wrapped.replace('Colors.white.withValues(alpha: 0.06)', 'const Color(0xFFF59E0B)'))
            assert ink['scan'](ink_file.relative_to(copy).as_posix()) == []
            results['recordings wrapped ink opt-in and negatives'] = 'PASS'
        finally:
            ink_file.unlink()

        def run():
            output = io.StringIO()
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                code = checker.main()
            return code, output.getvalue()

        code, output = run()
        assert code == 0, output
        results['unmodified staged tree'] = 'PASS'
        checker.RECORDINGS_COMPLETE = False

        def probe(name, relative, text, expected=None):
            file = copy / relative
            before = file.read_text() if file.exists() else None
            file.parent.mkdir(parents=True, exist_ok=True)
            try:
                if text is None:
                    file.unlink()
                else:
                    assert text != before, name
                    file.write_text(text)
                code, output = run()
                if expected:
                    assert code != 0 and expected in output, (name, output)
                    results[name] = 'rejected by real main'
                else:
                    assert code == 0, (name, output)
                    results[name] = 'PASS'
            finally:
                if before is None:
                    file.unlink(missing_ok=True)
                else:
                    file.write_text(before)

        probe('missing staged facade', facade, None, 'Recordings facade is missing')
        probe('501-line destination', base + 'presentation/size_probe.dart', '\n' * 501, '500-line recordings extraction limit')
        probe('service outside bridge', base + 'presentation/service_probe.dart', "import 'package:debrify/services/live_recording_service.dart';\n", 'Recordings service import outside its exact legacy bridge')
        probe('bridge service allowed', bridge + 'service_probe.dart', "import 'package:debrify/services/live_recording_service.dart';\n")
        probe('facade back import', bridge + 'facade_probe.dart', "import 'package:debrify/screens/settings/recordings_page.dart';\n", 'Recordings feature imports its facade')
        probe('screen import', bridge + 'screen_probe.dart', "import 'package:debrify/screens/settings/iptv_settings_page.dart';\n", 'Recordings feature imports a screen')
        for uri in ['package:debrify/services/video_player_launcher.dart', 'package:debrify/features/player_launch/models/video_player_launch_args.dart', 'package:media_kit/media_kit.dart', 'package:debrify/screens/video_player/player.dart']:
            probe('layout playback import ' + uri, bridge + 'recordings_hub_layout.dart', "import '" + uri + "';\n", 'Recordings playback import outside its registered handoff file')
        probe('registered handoff launcher allowed', bridge + 'recordings_hub_actions.dart', "import 'package:debrify/services/video_player_launcher.dart';\n")
        for uri in ['package:http/http.dart', 'package:shared_preferences/shared_preferences.dart', 'package:sqflite/sqflite.dart']:
            probe('bridge persistence import ' + uri, bridge + 'persistence_probe.dart', "import '" + uri + "';\n", 'view directly imports data/platform API')
        probe('TEMP outside bridge', base + 'presentation/temp_probe.dart', '// TEMP(recordings)\n', 'Recordings temporary cross-call outside its exact legacy bridge')
        probe('staged bridge TEMP allowed', bridge + 'temp_probe.dart', '// TEMP(recordings)\n')
        probe('keep-alive forbidden', base + 'presentation/keep_alive_probe.dart', '// KeepAlive\n', 'Recordings adds keep-alive ownership')

        # Completion probes use the actual facade once complete; earlier stages
        # use a size-only fixture without advancing the real source tree.
        completed = ((copy / facade).read_text() if completed_tree else
                     '// recordings completion guard fixture\n' * checker.RECORDINGS_FACADE_CAP)
        (copy / facade).write_text(completed)
        checker.RECORDINGS_COMPLETE = True
        checker.COMPOSITION_ROOTS = {*checker.COMPOSITION_ROOTS, facade}
        code, output = run()
        assert code == 0, output
        results['real completed facade' if completed_tree else 'completed facade fixture'] = 'PASS'
        probe('missing completed facade', facade, None, 'missing')
        probe('facade cap plus one', facade, completed + '// extra\n', 'recordings facade limit')
        probe('completed facade TEMP', facade, completed.replace('//', '// TEMP(recordings)', 1), 'Recordings temporary cross-call remains in the facade')
        probe('completed bridge TEMP', bridge + 'temp_probe.dart', '// TEMP(recordings)\n', 'Recordings temporary cross-call outside its exact legacy bridge')
        code, output = run()
        assert code == 0, output
        print(json.dumps(results, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
