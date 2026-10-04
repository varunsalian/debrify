#!/usr/bin/env python3
"""Run the real architecture checker on temporary Spotlight fixture trees."""
import contextlib
import io
import shutil
import tempfile
from pathlib import Path
from unittest.mock import patch

import check_search_architecture as guard


def main():
    with tempfile.TemporaryDirectory(dir=guard.ROOT / '.dart_tool/spotlight_board') as scratch:
        root = Path(scratch)
        shutil.copytree(guard.ROOT / 'lib', root / 'lib')
        def run(expected=None):
            output = io.StringIO()
            with patch.object(guard, 'ROOT', root), contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                result = guard.main()
            if expected is None:
                assert result == 0, output.getvalue()
            else:
                assert result == 1 and expected in output.getvalue(), output.getvalue()
        run()
        pure = root / 'lib/features/spotlight_board/presentation/guard_fixture.dart'
        bridge = root / guard.SPOTLIGHT_BOARD_BRIDGE / 'guard_fixture.dart'
        bridge.parent.mkdir(parents=True, exist_ok=True)
        home = root / 'lib/features/home/presentation/spotlight_guard_fixture.dart'
        service = "import 'package:debrify/services/stremio_service.dart';\n"
        for file, source, error in [
            (pure, service, 'outside the exact legacy bridge'),
            (bridge, "import 'package:http/http.dart';\n", 'view directly imports'),
            (bridge, "import 'package:shared_preferences/shared_preferences.dart';\n", 'view directly imports'),
            (bridge, "import 'package:sqflite/sqflite.dart';\n", 'view directly imports'),
            (bridge, "import 'package:debrify/widgets/home/spotlight_board.dart';\n", 'imports its facade'),
            (bridge, "import 'package:debrify/features/home/presentation/home_spotlight_boards.dart';\n", 'implementation cross-import'),
            (home, "import 'package:debrify/features/spotlight_board/presentation/guard_fixture.dart';\n", 'implementation cross-import'),
            (pure, '// line\n' * 501, '500-line spotlight board'),
            (pure, '// TEMP(spotlight_board)\n', 'temporary cross-call'),
            (bridge, '// AutomaticKeepAliveClientMixin\n', 'keep-alive or playback engine'),
            (bridge, "import 'package:media_kit/media_kit.dart';\n", 'keep-alive or playback engine'),
        ]:
            file.write_text(source)
            try:
                run(error)
            finally:
                file.unlink()
        bridge.write_text(service)
        run()
        bridge.unlink()
        # Missing feature must fail instead of making its scans disappear.
        feature = root / 'lib/features/spotlight_board'
        backup = root / 'lib/features/spotlight_board_saved'
        feature.rename(backup)
        try:
            run('Registered spotlight board directory is missing')
        finally:
            backup.rename(feature)
        run()
    print('Spotlight real architecture positives and missing/size/import/ownership negatives: PASS')


if __name__ == '__main__':
    main()
