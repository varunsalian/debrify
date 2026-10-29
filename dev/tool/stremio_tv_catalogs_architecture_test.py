#!/usr/bin/env python3
"""Exercise real staged/completed catalog guards on an owned source-tree copy."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import tempfile


def main():
    root = Path(__file__).resolve().parents[2]
    spec = importlib.util.spec_from_file_location('catalogs_architecture', root / 'dev/tool/check_search_architecture.py')
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    with tempfile.TemporaryDirectory(prefix='stremio_tv_catalogs_architecture_', dir=root / '.dart_tool') as directory:
        copy = Path(directory)
        shutil.copytree(root / 'lib', copy / 'lib')
        checker.ROOT = copy
        base = 'lib/features/stremio_tv_catalogs/'
        bridge = checker.STREMIO_TV_CATALOGS_BRIDGE
        facade = checker.STREMIO_TV_CATALOGS_FACADE
        results = {}

        def run():
            output = io.StringIO()
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                result = checker.main()
            return result, output.getvalue()

        assert run()[0] == 0, run()[1]
        results['unmodified staged tree'] = 'PASS'
        checker.STREMIO_TV_CATALOGS_COMPLETE = False

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

        probe('unregistered feature over cap', base + 'application/size_probe.dart', '\n' * 501, '500-line Stremio TV catalogs extraction limit')
        probe('facade back import', bridge + 'facade_probe.dart', "import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_local_catalogs_dialog.dart';\n", 'feature imports its facade')
        probe('service outside bridge/data', base + 'application/service_probe.dart', "import 'package:debrify/services/storage/stremio_catalog_storage.dart';\n", 'service import outside data')
        probe('data service allowed', base + 'data/storage_probe.dart', "import 'package:debrify/services/storage/stremio_catalog_storage.dart';\n")
        probe('bridge service allowed', bridge + 'storage_probe.dart', "import 'package:debrify/services/storage/stremio_catalog_storage.dart';\n")
        allowed, uri = checker.STREMIO_TV_CATALOGS_URL_IMPORT_HTTP_IMPORT
        probe('exact HTTP pair allowed', allowed, "import '" + uri + "' as http;\n")
        for layer in ['data', 'application', 'models', 'presentation/legacy_stremio_tv_catalogs']:
            probe('HTTP forbidden in ' + layer, base + layer + '/http_probe.dart', "import '" + uri + "';\n", 'HTTP import outside its exact URL-dialog pair')
        probe('HTTP sibling URI forbidden', allowed, "import 'package:http/io_client.dart';\n", 'HTTP import outside its exact URL-dialog pair')
        probe('catalogs to TV implementation', base + 'application/peer_probe.dart', "import 'package:debrify/features/stremio_tv/application/peer.dart';\n", 'implementation cross-import outside models')
        probe('TV to catalogs implementation', 'lib/features/stremio_tv/application/catalogs_probe.dart', "import 'package:debrify/features/stremio_tv_catalogs/data/local_catalog_export.dart';\n", 'implementation cross-import outside models')
        probe('peer model allowed', base + 'application/peer_probe.dart', "import 'package:debrify/features/stremio_tv/models/peer.dart';\n")
        probe('models UI forbidden', base + 'models/ui_probe.dart', "import 'package:flutter/material.dart';\n", 'models imports/exports UI')
        probe('TEMP outside bridge', base + 'application/temp_probe.dart', '// TEMP(stremio_tv_catalogs)\n', 'temporary cross-call outside its exact legacy bridge')
        probe('staged bridge TEMP allowed', bridge + 'temp_probe.dart', '// TEMP(stremio_tv_catalogs)\n')

        measured = checker.STREMIO_TV_CATALOGS_SIZE_EXCEPTIONS
        for relative, cap in measured.items():
            assert (root / relative).is_file(), relative
            assert cap == len((root / relative).read_text().splitlines()), (relative, cap)
            probe('measured exception growth ' + relative, relative, '\n' * (cap + 1), str(cap) + '-line Stremio TV catalogs extraction limit')
        synthetic = bridge + 'local_catalog_trakt_import_dialog.dart'
        checker.STREMIO_TV_CATALOGS_SIZE_EXCEPTIONS = {**measured, synthetic: 554}
        probe('exact synthetic exception allowed', synthetic, '\n' * 554)
        probe('synthetic exception growth', synthetic, '\n' * 555, '554-line Stremio TV catalogs extraction limit')
        checker.STREMIO_TV_CATALOGS_SIZE_EXCEPTIONS = measured

        # Completion negatives use a pure-export fixture until Step 3 creates it.
        pure = (
            "export 'package:debrify/features/stremio_tv_catalogs/data/local_catalog_export.dart'\n"
            "    show LocalCatalogExportPayload, LocalCatalogExporter;\n"
            "export 'package:debrify/features/stremio_tv_catalogs/data/local_catalog_importer.dart'\n"
            "    show LocalCatalogImporter;\n"
            "export 'package:debrify/features/stremio_tv_catalogs/presentation/legacy_stremio_tv_catalogs/local_catalog_editor_dialog.dart'\n"
            "    show StremioTvLocalCatalogEditorDialog;\n"
            "export 'package:debrify/features/stremio_tv_catalogs/presentation/legacy_stremio_tv_catalogs/local_catalogs_manage_dialog.dart'\n"
            "    show StremioTvLocalCatalogsDialog;\n"
        )
        (copy / facade).write_text(pure)
        checker.STREMIO_TV_CATALOGS_FACADE_CAP = len(pure.splitlines())
        checker.STREMIO_TV_CATALOGS_COMPLETE = True
        checker.COMPOSITION_ROOTS = {*checker.COMPOSITION_ROOTS, facade}
        assert run()[0] == 0, run()[1]
        results['completed fixture'] = 'PASS'
        probe('missing facade', facade, None, 'missing')
        probe('facade declaration', facade, pure + 'class Extra {}\n', 'only export directives')
        probe('facade import', facade, "import 'package:flutter/material.dart';\n" + pure, 'only export directives')
        probe('facade over cap', facade, pure + '// extra\n', 'facade limit')
        probe('dropped original name', facade, pure.replace('show LocalCatalogImporter;', 'show Extra;'), 'still export the original five names')
        probe('wrong export destination', facade, pure.replace('features/stremio_tv_catalogs/data/local_catalog_importer.dart', 'services/storage/stremio_catalog_storage.dart'), 'export its feature destinations')
        probe('completed bridge TEMP', bridge + 'temp_probe.dart', '// TEMP(stremio_tv_catalogs)\n', 'temporary cross-call outside its exact legacy bridge')
        probe('completed facade TEMP', facade, pure + '// TEMP(stremio_tv_catalogs)\n', 'temporary cross-call remains in the facade')
        assert run()[0] == 0, run()[1]
        print(json.dumps(results, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
