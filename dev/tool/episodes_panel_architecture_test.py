#!/usr/bin/env python3
"""Run the real architecture checker on an owned temporary source-tree copy."""
import contextlib
import importlib.util
import io
from pathlib import Path
import shutil
import tempfile


def main():
    root = Path(__file__).resolve().parents[2]
    spec = importlib.util.spec_from_file_location(
        'episodes_architecture', root / 'dev/tool/check_search_architecture.py')
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    with tempfile.TemporaryDirectory(prefix='episodes_panel_architecture_', dir=root / '.dart_tool') as directory:
        copy = Path(directory)
        shutil.copytree(root / 'lib', copy / 'lib')
        checker.ROOT = copy
        # Simulate peers landing: the named two-direction rule must already apply.
        checker.FEATURES += ('catalog_detail', 'detail_showcase')

        def run():
            output = io.StringIO()
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                code = checker.main()
            return code, output.getvalue()

        assert run()[0] == 0, run()[1]
        model = copy / 'lib/features/episodes_panel/models/episodes_panel_view.dart'
        saved = model.read_text()
        exact_dto = "import 'package:debrify/services/trakt/trakt_episode_model.dart';\n"
        model.write_text(exact_dto + 'class Fixture {}\n')
        assert run()[0] == 0, run()[1]
        model.write_text(saved)

        def rejects(path, text, message):
            file = copy / path
            existed = file.exists()
            before = file.read_text() if existed else None
            file.parent.mkdir(parents=True, exist_ok=True)
            try:
                file.write_text(text)
                code, output = run()
                assert code != 0 and message in output, (path, output)
            finally:
                if existed:
                    file.write_text(before)
                else:
                    file.unlink()
            print('Episodes architecture negative:', path, message, 'rejected')

        base = 'lib/features/episodes_panel/'
        rejects(base + 'models/episodes_panel_view.dart',
                "import 'package:debrify/services/trakt/trakt_service.dart';\n",
                'episodes panel service/storage import')
        rejects(base + 'models/second_model.dart', exact_dto,
                'episodes panel service/storage import')
        rejects(base + 'application/second_policy.dart', exact_dto,
                'episodes panel service/storage import')
        rejects(base + 'models/ui_model.dart', "import 'package:flutter/material.dart';\n",
                'models imports/exports UI')
        rejects(base + 'models/di_model.dart', "import 'package:flutter_riverpod/flutter_riverpod.dart';\n",
                'models depends on state/DI')
        rejects(base + 'application/second_policy.dart', '// TEMP(episodes_panel)\n',
                'episodes panel temporary cross-call')
        rejects(base + 'presentation/second_view.dart',
                "import 'package:debrify/widgets/episodes_panel.dart';\n",
                'episodes panel feature imports its facade')
        rejects(base + 'application/second_policy.dart', '\n' * 500 + '// extra\n',
                '500-line episodes panel extraction limit')
        for symbol in ('VideoPlayerLauncher', 'VideoPlayerScreen', 'SeriesSourceFetcher',
                       'mergeSources', 'TorrentPlaybackService'):
            rejects(base + 'presentation/legacy_episodes_panel/second_section.dart',
                    'void f() { ' + symbol + '(); }\n',
                    'episodes panel contains a playback/source-launch symbol')
        for package in ('http/http.dart', 'shared_preferences/shared_preferences.dart', 'sqflite/sqflite.dart'):
            rejects(base + 'presentation/legacy_episodes_panel/second_section.dart',
                    "import 'package:" + package + "';\n", 'view directly imports data/platform API')
        for peer in ('merged_detail', 'catalog_detail', 'detail_showcase'):
            rejects(base + 'presentation/second_view.dart',
                    "import 'package:debrify/features/" + peer + "/presentation/private.dart';\n",
                    'episodes panel/detail implementation cross-import')
            rejects('lib/features/' + peer + '/presentation/second_view.dart',
                    "import 'package:debrify/features/episodes_panel/presentation/private.dart';\n",
                    'episodes panel/detail implementation cross-import')
            for importer, target in [('episodes_panel', peer), (peer, 'episodes_panel')]:
                path = copy / ('lib/features/' + importer + '/models/fixture_model.dart')
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("import 'package:debrify/features/" + target + "/models/public.dart';\n")
                assert run()[0] == 0, run()[1]
                path.unlink()
        # Exercise completion checks before their production activation at step 7.
        checker.EPISODES_PANEL_COMPLETE = True
        checker.COMPOSITION_ROOTS = {*checker.COMPOSITION_ROOTS, checker.EPISODES_PANEL_FACADE}
        facade = copy / checker.EPISODES_PANEL_FACADE
        facade.write_text('class EpisodesPanel {}\n')
        deps = copy / (base + 'presentation/legacy_episodes_panel/episodes_panel_deps.dart')
        temporary = '// TEMP(episodes_panel): root getter stays in the facade until step 6.\n'
        if deps.exists() and temporary in deps.read_text():
            code, output = run()
            assert code != 0 and 'episodes panel temporary cross-call' in output
            # Only the synthetic completion copy removes this staged marker.
            deps.write_text(deps.read_text().replace(temporary, ''))
            print('Episodes actual staged marker rejects premature completion')
        assert run()[0] == 0, run()[1]
        facade.unlink()
        assert run()[0] != 0 and 'missing' in run()[1]
        facade.write_text('class EpisodesPanel {}\n')
        rejects(checker.EPISODES_PANEL_FACADE, '\n' * checker.EPISODES_PANEL_FACADE_LIMIT + '// extra\n',
                'episodes panel facade limit')
        rejects(checker.EPISODES_PANEL_FACADE, '// TEMP(episodes_panel)\n',
                'episodes panel temporary cross-call remains in the facade')
        rejects(base + 'presentation/legacy_episodes_panel/second_section.dart',
                '// TEMP(episodes_panel)\n', 'episodes panel temporary cross-call')
    print('Episodes architecture: real tree-copy positives and all negatives PASS')


if __name__ == '__main__':
    main()
