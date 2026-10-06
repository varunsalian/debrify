"""Exercise the actual edit-profile architecture guard on isolated sources."""
import contextlib
import io
import shutil
import tempfile
from pathlib import Path


def self_test():
    import check_search_architecture as guard
    root = guard.ROOT
    assert guard.EDIT_PROFILE_COMPLETE
    facade = guard.EDIT_PROFILE_FACADE
    surface = 'lib/features/edit_profile/presentation/edit_profile_tv_surfaces.dart'
    bridge = guard.EDIT_PROFILE_BRIDGE + 'edit_profile_save.dart'
    parent = root / '.dart_tool/edit_profile_parser/architecture'
    parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=parent) as temporary:
        scratch = Path(temporary)
        shutil.copytree(root / 'lib', scratch / 'lib')
        guard.ROOT = scratch
        try:
            def main_result():
                out, err = io.StringIO(), io.StringIO()
                with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                    result = guard.main()
                return result, out.getvalue() + err.getvalue()

            result, output = main_result()
            assert result == 0, output
            print('Edit profile completed architecture unchanged-tree positive: PASS')
            path = scratch / facade
            original = path.read_text()
            path.unlink()
            result, output = main_result()
            assert result == 1 and facade in output and 'missing' in output.lower(), output
            path.write_text(original)
            print('Edit profile architecture facade missing: rejected')
            cases = [
                ('facade cap + 1', facade, '\n' * (guard.EDIT_PROFILE_FACADE_CAP + 1), 'facade limit'),
                ('facade TEMP', facade, original + '// TEMP(edit_profile)\n', 'temporary cross-call'),
                ('feature TEMP', bridge, '// TEMP(edit_profile)\n', 'temporary cross-call'),
                ('surface service import', surface, "import 'package:debrify/services/profiles/profile_registry.dart';\n", 'service/platform import'),
                ('surface dart:io import', surface, "import 'dart:io';\n", 'service/platform import'),
                ('surface file_picker import', surface, "import 'package:file_picker/file_picker.dart';\n", 'service/platform import'),
                ('surface Clipboard', surface, 'void probe() { Clipboard.setData(value); }\n', 'Clipboard access'),
                ('facade back-import', bridge, "import 'package:debrify/screens/profiles/edit_profile_screen.dart';\n", 'imports its facade'),
                ('feature 501 lines', surface, '\n' * 501, '500-line'),
                ('outbound feature import', surface, "import 'package:debrify/features/home/models/probe.dart';\n", 'cross-feature import'),
                ('inbound feature import', 'lib/features/home/models/edit_profile_guard_probe.dart', "import 'package:debrify/features/edit_profile/models/edit_profile_snapshot.dart';\n", 'cross-feature import'),
                ('unrelated ceiling', 'lib/features/home/edit_profile_guard_probe.dart', '\n' * 801, '800-line ceiling'),
            ]
            for label, relative, mutant, reason in cases:
                path = scratch / relative
                existing = path.read_text() if path.exists() else None
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(mutant)
                problems = guard.violations(path)
                assert any(reason in problem for problem in problems), (label, problems)
                if existing is None:
                    path.unlink()
                else:
                    path.write_text(existing)
                print('Edit profile architecture ' + label + ': rejected')
            result, output = main_result()
            assert result == 0, output
            print('Edit profile completed architecture: PASS; 13 negatives')
        finally:
            guard.ROOT = root
