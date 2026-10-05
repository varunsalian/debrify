#!/usr/bin/env python3
"""Exercise real Debrify TV guards on an owned temporary source-tree copy."""
import contextlib
import importlib.util
import io
from pathlib import Path
import shutil
import tempfile


def self_test(package=None):
    root = Path(__file__).resolve().parents[2]
    spec = importlib.util.spec_from_file_location('tv_architecture', root / 'dev/tool/check_search_architecture.py')
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    with tempfile.TemporaryDirectory(prefix='debrify_tv_architecture_', dir=root / '.dart_tool') as directory:
        copy = Path(directory)
        shutil.copytree(root / 'lib', copy / 'lib')
        checker.ROOT = copy
        base = 'lib/features/debrify_tv/'
        bridge = checker.DEBRIFY_TV_BRIDGE

        def run():
            output = io.StringIO()
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                result = checker.main()
            return result, output.getvalue()

        assert run()[0] == 0, run()[1]

        def probe(path, text, message=None):
            file = copy / path
            before = file.read_text() if file.exists() else None
            file.parent.mkdir(parents=True, exist_ok=True)
            try:
                file.write_text(text)
                result, output = run()
                if message:
                    assert result != 0 and path in output and message in output, (path, output)
                    print('TV real architecture ' + message + ': rejected')
                else:
                    assert result == 0, output
            finally:
                if before is None:
                    file.unlink()
                else:
                    file.write_text(before)

        # Scanning is active before completion and before a feature exists.
        assert not checker.DEBRIFY_TV_COMPLETE
        probe(base + 'application/policy.dart', '\n' * 500 + '// extra\n', '500-line Debrify TV extraction limit')
        probe(bridge + 'unrelated.dart', '\n' * 800 + '// extra\n', '500-line Debrify TV extraction limit')
        probe(base + 'presentation/view.dart', "import 'package:debrify/services/debrify_tv_repository.dart';\n", 'service import outside its exact legacy bridge')
        probe(bridge + 'facade_import.dart', "import 'package:debrify/screens/magic_tv_screen.dart';\n", 'feature imports its facade')
        probe(base + 'models/model.dart', "import 'package:flutter/material.dart';\n", 'models imports/exports UI')
        probe(base + 'application/policy.dart', "import 'package:debrify/screens/video_player_screen.dart';\n", 'application imports/exports UI')
        probe(bridge + 'storage.dart', "import 'package:debrify/services/debrify_tv_repository.dart';\n")
        allowed, uri = checker.DEBRIFY_TV_URL_IMPORT_HTTP_IMPORT
        probe(allowed, "import '" + uri + "' as http;\n")
        for path in [base + 'presentation/url_import.dart', bridge + 'wrong_url.dart']:
            probe(path, "import '" + uri + "';\n", 'view directly imports data/platform API')
        for uri in ['package:http/io_client.dart', 'package:shared_preferences/shared_preferences.dart', 'package:sqflite/sqflite.dart']:
            probe(allowed, "import '" + uri + "';\n", 'view directly imports data/platform API')
        probe(base + 'presentation/view.dart', '// TEMP(debrify_tv)\n', 'temporary cross-call outside its exact legacy bridge')
        # Actual exception values stay zero until creation. Synthetic measured
        # values test both caps, their exact filenames, and growth rejection.
        assert set(checker.DEBRIFY_TV_SIZE_EXCEPTIONS.values()) == {0}
        for path, cap in [(bridge + 'debrify_tv_quick_play.dart', 930), (bridge + 'debrify_tv_channel_switch.dart', 530)]:
            checker.DEBRIFY_TV_SIZE_EXCEPTIONS[path] = cap
            probe(path, '\n' * cap)
            probe(path, '\n' * cap + '// extra\n', str(cap) + '-line Debrify TV extraction limit')
        probe(bridge + 'other_large.dart', '\n' * 930, '500-line Debrify TV extraction limit')
        probe(bridge + 'temporary.dart', '// TEMP(debrify_tv)\n')
        checker.DEBRIFY_TV_COMPLETE = True
        facade = copy / checker.DEBRIFY_TV_FACADE
        facade.write_text('class DebrifyTVScreen {}\n')
        assert run()[0] == 0, run()[1]
        probe(bridge + 'temporary.dart', '// TEMP(debrify_tv)\n', 'temporary cross-call outside its exact legacy bridge')
        probe(checker.DEBRIFY_TV_FACADE, '\n' * checker.DEBRIFY_TV_FACADE_CAP + '// extra\n', 'Debrify TV facade limit')
        probe(checker.DEBRIFY_TV_FACADE, '// TEMP(debrify_tv)\n', 'temporary cross-call remains in the facade')
        facade.unlink()
        assert run()[0] != 0 and 'missing' in run()[1]
    print('TV architecture: real copy positives, unconditional scans and negatives PASS')


if __name__ == '__main__':
    self_test()
