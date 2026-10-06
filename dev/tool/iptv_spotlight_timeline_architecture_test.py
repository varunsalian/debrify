#!/usr/bin/env python3
"""Exercise timeline guards through the real checker on an owned source copy."""
import contextlib
import importlib.util
import io
from pathlib import Path
import shutil
import tempfile


def self_test(package=None):
    root = Path(__file__).resolve().parents[2]
    spec = importlib.util.spec_from_file_location('timeline_architecture', root / 'dev/tool/check_search_architecture.py')
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    with tempfile.TemporaryDirectory(prefix='iptv_spotlight_timeline_architecture_', dir=root / '.dart_tool') as directory:
        copy = Path(directory)
        shutil.copytree(root / 'lib', copy / 'lib')
        checker.ROOT = copy
        base = 'lib/features/iptv_spotlight_timeline/'
        bridge = checker.IPTV_SPOTLIGHT_TIMELINE_BRIDGE
        facade_path = checker.IPTV_SPOTLIGHT_TIMELINE_FACADE

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
                    assert result != 0 and message in output, (path, output)
                    print('Timeline real architecture ' + message + ': rejected')
                else:
                    assert result == 0, output
            finally:
                if before is None:
                    file.unlink()
                else:
                    file.write_text(before)

        checker.IPTV_SPOTLIGHT_TIMELINE_COMPLETE = False
        probe(base + 'presentation/size_probe.dart', '\n' * 501, '500-line IPTV spotlight timeline extraction limit')
        probe(bridge + 'size_probe.dart', '\n' * 501, '500-line IPTV spotlight timeline extraction limit')
        probe(base + 'presentation/service_probe.dart', "import 'package:debrify/services/iptv_epg_service.dart';\n", 'service import outside its exact legacy bridge')
        probe(bridge + 'service_probe.dart', "import 'package:debrify/services/iptv_epg_service.dart';\n")
        probe(bridge + 'facade_probe.dart', "export 'package:debrify/widgets/iptv/spotlight/spotlight_live_timeline.dart';\n", 'feature imports its facade')
        for uri in ['package:http/http.dart', 'package:shared_preferences/shared_preferences.dart', 'package:sqflite/sqflite.dart']:
            probe(bridge + 'storage_probe.dart', "import '" + uri + "';\n", 'view directly imports data/platform API')
        probe(base + 'presentation/temp_probe.dart', '// TEMP(iptv_spotlight_timeline)\n', 'temporary cross-call outside its exact legacy bridge')
        probe(bridge + 'temp_probe.dart', '// TEMP(iptv_spotlight_timeline)\n')
        for text in ['// AutomaticKeepAliveClientMixin\n', '// IndexedStack\n', "import 'package:media_kit/media_kit.dart';\n", "import 'package:debrify/services/video_player_launcher.dart';\n", "import 'package:debrify/features/player_launch/presentation/player.dart';\n"]:
            probe(base + 'presentation/ownership_probe.dart', text, 'keep-alive or playback engine ownership')
        for peer in ['iptv']:
            probe(base + 'presentation/peer_probe.dart', "import 'package:debrify/features/" + peer + "/presentation/view.dart';\n", 'implementation cross-import')
            probe('lib/features/' + peer + '/presentation/timeline_probe.dart', "import 'package:debrify/features/iptv_spotlight_timeline/presentation/spotlight_timeline_parts.dart';\n", 'implementation cross-import')
            probe(base + 'presentation/peer_probe.dart', "import 'package:debrify/features/" + peer + "/models/channel.dart';\n")
            probe('lib/features/' + peer + '/presentation/timeline_probe.dart', "import 'package:debrify/features/iptv_spotlight_timeline/models/channel.dart';\n")
        assert not checker.IPTV_SPOTLIGHT_TIMELINE_SIZE_EXCEPTIONS
        checker.IPTV_SPOTLIGHT_TIMELINE_COMPLETE = True
        facade = copy / facade_path
        facade.write_text('// Composition root: timeline widget view and bound sections.\nclass SpotlightLiveTimeline {}\n')
        assert run()[0] == 0, run()[1]
        probe(facade_path, '\n' * checker.IPTV_SPOTLIGHT_TIMELINE_FACADE_CAP + '// extra\n', 'IPTV spotlight timeline facade limit')
        probe(facade_path, '// TEMP(iptv_spotlight_timeline)\n', 'temporary cross-call remains in the facade')
        probe(bridge + 'temp_probe.dart', '// TEMP(iptv_spotlight_timeline)\n', 'temporary cross-call outside its exact legacy bridge')
        facade.unlink()
        result, output = run()
        assert result != 0 and 'missing' in output and facade_path in output, output
    print('Timeline architecture: real copy positives, unconditional scans and negatives PASS')


if __name__ == '__main__':
    self_test()
