#!/usr/bin/env python3
"""Probe the real staged and completed AllDebrid architecture guard."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import tempfile


def main():
    root = Path(__file__).resolve().parents[2]
    spec = importlib.util.spec_from_file_location('alldebrid_architecture', root / 'dev/tool/check_search_architecture.py')
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    config = json.loads((root / 'dev/tool/alldebrid_files_checker_config.json').read_text())
    assert set(config['playback_files']) == checker.ALLDEBRID_PLAYBACK_FILES
    assert set(config['download_files']) == checker.ALLDEBRID_DOWNLOAD_FILES
    with tempfile.TemporaryDirectory(prefix='alldebrid-architecture-', dir=root / '.dart_tool') as directory:
        copy = Path(directory)
        shutil.copytree(root / 'lib', copy / 'lib')
        checker.ROOT = copy
        base = 'lib/features/alldebrid_files/'
        bridge, facade = checker.ALLDEBRID_BRIDGE, checker.ALLDEBRID_FACADE
        results = {}

        def run():
            output = io.StringIO()
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                result = checker.main()
            return result, output.getvalue()

        assert run()[0] == 0, run()[1]
        results['real tree positive'] = 'PASS'
        checker.ALLDEBRID_COMPLETE = False

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
                result, output = run()
                if expected:
                    assert result != 0 and relative in output and expected in output, (name, output)
                    results[name] = 'rejected by real main'
                else:
                    assert result == 0, (name, output)
                    results[name] = 'PASS'
            finally:
                if before is None:
                    file.unlink(missing_ok=True)
                else:
                    file.write_text(before)

        probe('destination cap', base + 'application/size_probe.dart', '\n' * 501, '500-line AllDebrid extraction limit')
        for uri in ['package:debrify/screens/alldebrid/alldebrid_files_screen.dart', '../../../../screens/alldebrid/alldebrid_files_screen.dart']:
            probe('facade back import ' + uri, bridge + 'facade_probe.dart', "import '" + uri + "';\n", 'AllDebrid feature imports its facade')
        for layer in ['application', 'models', 'data', 'presentation', 'presentation/legacy_alldebrid_sibling']:
            for uri in ['package:debrify/services/alldebrid_service.dart', 'package:flutter/services.dart', 'package:http/http.dart', 'package:debrify/services/video_player_launcher.dart', 'package:debrify/screens/video_player_screen.dart', 'package:debrify/features/player_launch/models/video_player_launch_args.dart']:
                probe(layer + ' forbidden ' + uri, base + layer + '/service_probe.dart', "import '" + uri + "';\n", 'AllDebrid service/platform/launcher import outside its exact legacy bridge')
        for uri in ['package:debrify/services/alldebrid_service.dart', 'package:flutter/services.dart', 'package:http/http.dart', 'package:debrify/services/video_player_launcher.dart']:
            probe('bridge allowed ' + uri, bridge + 'service_probe.dart', "import '" + uri + "';\n")
        for peer in sorted(checker.ALLDEBRID_PEERS):
            # Premiumize is deliberately unregistered in this copy. Both scans
            # must work even without a peer entry in FEATURES.
            if peer == 'premiumize_files':
                checker.FEATURES = tuple(f for f in checker.FEATURES if f != peer)
            for layer in ['models', 'application', 'presentation']:
                probe('forward ' + peer + '/' + layer, base + 'application/peer_probe.dart', "import 'package:debrify/features/" + peer + '/' + layer + "/peer.dart';\n", 'AllDebrid cloud peer cross-import (including models)')
                probe('reverse ' + peer + '/' + layer, 'lib/features/' + peer + '/models/alldebrid_probe.dart', "import 'package:debrify/features/alldebrid_files/" + layer + "/peer.dart';\n", 'AllDebrid cloud peer cross-import (including models)')
        for call in ['VideoPlayerLauncher.push(context, args);', 'VideoPlayerScreen();']:
            probe('wrong playback placement ' + call, bridge + 'placement_probe.dart', 'void run() { ' + call + ' }\n', 'AllDebrid playback handoff outside its registered section')
            probe('registered playback placement ' + call, next(iter(checker.ALLDEBRID_PLAYBACK_FILES)), 'void run() { ' + call + ' }\n')
        call = 'DownloadService.instance.enqueueDownload();'
        probe('wrong enqueue placement', bridge + 'placement_probe.dart', 'void run() { ' + call + ' }\n', 'AllDebrid enqueue outside its registered section')
        probe('registered enqueue placement', next(iter(checker.ALLDEBRID_DOWNLOAD_FILES)), 'void run() { ' + call + ' }\n')
        probe('TEMP outside bridge', base + 'application/temp_probe.dart', '// TEMP(alldebrid)\n', 'AllDebrid temporary cross-call outside its exact legacy bridge')
        probe('staged bridge TEMP', bridge + 'temp_probe.dart', '// TEMP(alldebrid)\n')
        synthetic = '// Measured composition fixture.\n'
        (copy / facade).write_text(synthetic)
        checker.ALLDEBRID_COMPLETE = True
        checker.ALLDEBRID_FACADE_CAP = len(synthetic.splitlines())
        checker.COMPOSITION_ROOTS = {*checker.COMPOSITION_ROOTS, facade}
        assert run()[0] == 0, run()[1]
        results['completed positive'] = 'PASS'
        probe('completed missing facade', facade, None, 'missing')
        probe('completed cap', facade, synthetic + '// extra\n', 'AllDebrid facade limit')
        probe('completed bridge TEMP', bridge + 'temp_probe.dart', '// TEMP(alldebrid)\n', 'AllDebrid temporary cross-call outside its exact legacy bridge')
        probe('completed facade TEMP', facade, synthetic + '// TEMP(alldebrid)\n', 'AllDebrid temporary cross-call remains in the facade')
        assert run()[0] == 0, run()[1]
        print(json.dumps(results, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
