#!/usr/bin/env python3
"""Exercise the real architecture main against an isolated complete tree copy."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FACADE = 'lib/widgets/detail/showcase_parts.dart'
STYLE = 'lib/features/detail_showcase/presentation/showcase_style.dart'
GROUNDS = 'lib/features/detail_showcase/presentation/showcase_grounds.dart'
GUIDE = 'lib/features/detail_showcase/presentation/showcase_guide.dart'


def main():
    # Keep the copy and its mutations inside the caller's dedicated worktree.
    with tempfile.TemporaryDirectory(prefix='detail_showcase_architecture_', dir=ROOT / '.dart_tool') as directory:
        tree = Path(directory)
        shutil.copytree(ROOT / 'lib', tree / 'lib')
        tool = tree / 'dev/tool/check_search_architecture.py'
        tool.parent.mkdir(parents=True)
        shutil.copy2(ROOT / 'dev/tool/check_search_architecture.py', tool)

        def run():
            return subprocess.run(['python3', str(tool)], cwd=tree, text=True, capture_output=True)

        positive = run()
        assert positive.returncode == 0, positive.stderr
        results = {'unmodified_complete_tree': 'PASS'}
        cases = [
            ('missing facade', FACADE, None, 'missing'),
            ('facade declaration', FACADE, lambda s: s + '\nclass ExtraShowcase {}\n', 'only export'),
            ('facade import', FACADE, lambda s: "import 'package:flutter/material.dart';\n" + s, 'only export'),
            ('facade over cap', FACADE, lambda s: s + '// measured cap negative\n' * 81, 'facade limit'),
            ('extra exported name', FACADE, lambda s: s.replace('show ShowcaseIdentity;', 'show ShowcaseIdentity, ExtraShowcase;'), 'eighteen names'),
            ('facade back import', STYLE, lambda s: "import 'package:debrify/widgets/detail/showcase_parts.dart';\n" + s, 'imports its facade'),
            ('merged implementation import', STYLE, lambda s: "import 'package:debrify/features/merged_detail/presentation/merged_detail_palette.dart';\n" + s, 'implementation cross-import'),
            ('catalog implementation import', STYLE, lambda s: "import 'package:debrify/features/catalog_detail/presentation/catalog_identity.dart';\n" + s, 'implementation cross-import'),
            ('reverse merged import', 'lib/features/merged_detail/presentation/merged_detail_palette.dart', lambda s: "import 'package:debrify/features/detail_showcase/presentation/showcase_style.dart';\n" + s, 'implementation cross-import'),
            ('unshown service', GROUNDS, lambda s: s.replace('show DebrifyImageCache;', ';'), 'show only allowed'),
            ('inexact service show list', GUIDE, lambda s: s.replace('ParentsGuideResult, ParentsGuideCategory, ParentsGuideItem', 'ParentsGuideResult, ParentsGuideCategory'), 'exact registered'),
            ('temporary marker', STYLE, lambda s: s + '// TEMP(detail_showcase) negative\n', 'temporary detail showcase'),
            ('feature over cap', STYLE, lambda s: s + '// measured file cap negative\n' * 501, '500-line detail showcase'),
            ('owned focus node', STYLE, lambda s: s + '\nfinal extraNode = FocusNode();\n', 'owned resource'),
            ('owned timer', STYLE, lambda s: s + '\nfinal extraTimer = Timer(Duration.zero, () {});\n', 'owned resource'),
            ('borrowed node disposal', STYLE, lambda s: s + '\nvoid disposeBorrowed() { node.dispose(); }\n', 'borrowed focus node'),
            ('playback engine', STYLE, lambda s: "import 'package:media_kit/media_kit.dart';\n" + s, 'playback implementation'),
            ('launcher import', STYLE, lambda s: "import 'package:debrify/services/video_player_launcher.dart';\n" + s, 'playback implementation'),
        ]
        for name, relative, mutate, expected in cases:
            path = tree / relative
            original = path.read_text()
            try:
                if mutate is None:
                    path.unlink()
                else:
                    changed = mutate(original)
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
