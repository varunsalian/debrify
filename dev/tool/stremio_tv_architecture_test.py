"""Exercise Stremio TV's exact opt-in rules through the real checker."""
import contextlib
import importlib.util
import io
from pathlib import Path
import shutil
import tempfile


def self_test():
    root = Path(__file__).resolve().parents[2]
    spec = importlib.util.spec_from_file_location(
        'stremio_tv_architecture', root / 'dev/tool/check_search_architecture.py')
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    with tempfile.TemporaryDirectory(prefix='stremio_tv_architecture_',
                                     dir=root / '.dart_tool') as directory:
        copy = Path(directory)
        shutil.copytree(root / 'lib', copy / 'lib')
        checker.ROOT = copy
        base = 'lib/features/stremio_tv/'
        bridge = checker.STREMIO_TV_BRIDGE

        def run():
            output = io.StringIO()
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                result = checker.main()
            return result, output.getvalue()

        assert run()[0] == 0, run()[1]
        checker.STREMIO_TV_COMPLETE = False

        def probe(path, text, message=None):
            file = copy / path
            before = file.read_text() if file.exists() else None
            file.parent.mkdir(parents=True, exist_ok=True)
            try:
                file.write_text(text)
                result, output = run()
                if message:
                    assert result != 0 and path in output and message in output, output
                    print('Stremio TV architecture rejected: ' + message)
                else:
                    assert result == 0, output
            finally:
                if before is None:
                    file.unlink()
                else:
                    file.write_text(before)

        for path in [bridge + 'unrelated.dart', base + 'presentation/unregistered.dart']:
            probe(path, '\n' * 500 + '// extra\n', '500-line Stremio TV extraction limit')
        probe(base + 'presentation/view.dart',
              "import 'package:debrify/services/stremio_tv_service.dart';\n",
              'service import outside its exact legacy bridge')
        probe(bridge + 'facade_import.dart',
              "import 'package:debrify/screens/stremio_tv/stremio_tv_screen.dart';\n",
              'feature imports its facade')
        probe(base + 'models/model.dart', "import 'package:flutter/material.dart';\n",
              'models imports/exports UI')
        probe(bridge + 'service.dart',
              "import 'package:debrify/services/stremio_tv_service.dart';\n")
        detail_import = "import 'package:debrify/screens/catalog_item_detail_screen.dart';\n"
        probe(checker.STREMIO_TV_CATALOG_DETAIL_CALLER, detail_import)
        for path in [bridge + 'other_catalog_detail.dart',
                     'lib/features/home/presentation/other_catalog_detail.dart']:
            probe(path, detail_import,
                  'feature imports the catalog-detail facade outside the existing Home caller')
        for uri in ['package:shared_preferences/shared_preferences.dart',
                    'package:sqflite/sqflite.dart']:
            probe(bridge + 'storage.dart', "import '" + uri + "';\n",
                  'view directly imports data/platform API')
        probe(bridge + 'stremio_tv_channel_actions.dart',
              "import 'package:debrify/services/video_player_launcher.dart';\n",
              'playback import outside its registered handoff files')
        probe(bridge + 'other_playback.dart', 'void play() { VideoPlayerLauncher.push(); }\n',
              'playback entry outside its registered handoff files')
        for path, cap in checker.STREMIO_TV_SIZE_EXCEPTIONS.items():
            assert cap == (len((root / path).read_text().splitlines())
                           if (root / path).exists() else 0), (path, cap)
            measured = cap or 713
            checker.STREMIO_TV_SIZE_EXCEPTIONS[path] = measured
            try:
                probe(path, '\n' * measured)
                probe(path, '\n' * measured + '// extra\n',
                      str(measured) + '-line Stremio TV extraction limit')
            finally:
                checker.STREMIO_TV_SIZE_EXCEPTIONS[path] = cap
        checker.STREMIO_TV_COMPLETE = True
        # Completion negatives use the owned copy; original bodies stay intact.
        for file in (copy / base).rglob('*.dart'):
            if 'TEMP(stremio_tv)' in file.read_text():
                result, output = run()
                assert result != 0 and file.relative_to(copy).as_posix() in output
                file.write_text('\n'.join(line for line in file.read_text().splitlines()
                                          if 'TEMP(stremio_tv)' not in line) + '\n')
        facade = copy / checker.STREMIO_TV_FACADE
        checker.STREMIO_TV_FACADE_CAP = checker.STREMIO_TV_FACADE_CAP or 119
        facade.write_text('class StremioTvScreen {}\n')
        assert run()[0] == 0, run()[1]
        probe(checker.STREMIO_TV_FACADE,
              '\n' * checker.STREMIO_TV_FACADE_CAP + '// extra\n', 'Stremio TV facade limit')
        probe(checker.STREMIO_TV_FACADE, '// TEMP(stremio_tv)\n',
              'temporary cross-call remains in the facade')
        probe(bridge + 'temporary.dart', '// TEMP(stremio_tv)\n',
              'temporary cross-call outside its exact legacy bridge')
        facade.unlink()
        assert run()[0] != 0 and 'missing' in run()[1]
    print('Stremio TV architecture: real-copy positives and negatives PASS')


if __name__ == '__main__':
    self_test()
