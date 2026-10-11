#!/usr/bin/env python3
"""Exercise the real Phase-1 video-player architecture guards on a copy."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[2]
    spec = importlib.util.spec_from_file_location(
        'vplayer_architecture', root / 'dev/tool/check_search_architecture.py')
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    assert 'video_player' in checker.FEATURES
    bridge = 'lib/features/video_player/presentation/legacy_video_player/'
    assert checker.VIDEO_PLAYER_BRIDGE == bridge
    assert bridge in checker.LEGACY_PLAYBACK_BRIDGES
    assert checker.VIDEO_PLAYER_FILE_CAP == 500
    common = Path(subprocess.check_output(
        ['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'],
        cwd=root, text=True).strip())
    evidence = common / 'refactor-evidence/vplayer/p1/architecture-fixtures'
    evidence.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=evidence) as directory:
        copy = Path(directory)
        shutil.copytree(root / 'lib', copy / 'lib')
        checker.ROOT = copy
        results = {}

        def run():
            output = io.StringIO()
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                code = checker.main()
            return code, output.getvalue()

        code, output = run()
        assert code == 0, output
        results['real production tree'] = 'PASS'

        def probe(name, relative, text, expected=None):
            path = copy / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            original = path.read_text() if path.exists() else None
            try:
                path.write_text(text)
                code, output = run()
                if expected:
                    assert code != 0 and expected in output, (name, output)
                    results[name] = 'rejected by real main'
                else:
                    assert code == 0, (name, output)
                    results[name] = 'PASS'
            finally:
                if original is None:
                    path.unlink()
                else:
                    path.write_text(original)

        base = 'lib/features/video_player/'
        facade = "import 'package:debrify/screens/video_player_screen.dart';\n"
        probe('facade package back import', bridge + 'probe.dart', facade,
              'Video-player feature imports its facade')
        probe('facade relative back import', base + 'models/probe.dart',
              "import '../../../screens/video_player_screen.dart';\n",
              'Video-player feature imports its facade')
        service = "import 'package:debrify/services/storage/video_resume_storage.dart';\n"
        probe('exact bridge service allowed', bridge + 'probe.dart', service)
        probe('lookalike bridge rejected', base + 'presentation/legacy_video_player_extra/probe.dart',
              service, 'Video-player service import outside its exact legacy bridge')
        probe('pure model legacy service', base + 'models/probe.dart', service,
              'pure video-player import outside its exact compatibility/type list')
        probe('pure helper UI context', base + 'application/probe.dart',
              'void action(BuildContext context) {}\n',
              'pure video-player declaration references UI/state context')
        probe('pure helper UI import', base + 'application/probe.dart',
              "import 'package:flutter/material.dart';\n", 'application imports/exports UI')
        probe('compatibility import scoped by file', base + 'models/probe.dart',
              "import 'package:debrify/models/iptv_playlist.dart';\n",
              'pure video-player import outside its exact compatibility/type list')
        probe('unknown pure utility rejected', base + 'application/vp_format.dart',
              "import 'package:debrify/utils/app_storage.dart';\n",
              'pure video-player import outside its exact compatibility/type list')
        probe('bridge HTTP rejected', bridge + 'probe.dart',
              "import 'package:http/http.dart';\n", 'view directly imports data/platform API')
        probe('501-line extraction rejected', base + 'presentation/probe.dart',
              '\n' * 501, '500-line video-player extraction limit')
        code, output = run()
        assert code == 0, output
        print(json.dumps(results, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
