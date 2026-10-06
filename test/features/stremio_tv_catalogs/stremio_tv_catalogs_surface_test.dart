import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../support/stremio_tv_catalogs_source.dart';

const catalogPublicNames = {
  'LocalCatalogExportPayload',
  'LocalCatalogExporter',
  'LocalCatalogImporter',
  'StremioTvLocalCatalogEditorDialog',
  'StremioTvLocalCatalogsDialog',
};
void main() {
  test(
    'resolved facade namespace is exactly the original five public names',
    () {
      final parser = File(
        '.dart_tool/stremio_tv_catalogs_surface_parser/.dart_tool/package_config.json',
      ).absolute.path;
      final result = Process.runSync('python3', [
        'dev/tool/stremio_tv_catalogs_surface.py',
        '--parser-package',
        parser,
        '--source',
        catalogsFacade,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        (jsonDecode(result.stdout as String) as List).toSet(),
        catalogPublicNames,
      );
      for (final name in catalogPublicNames) {
        expect(catalogsDeclaration(name), contains('class $name'));
      }
      if (catalogsComplete) {
        final source = File(catalogsFacade).readAsStringSync();
        expect(
          RegExp(
            r'^(?:class|enum|typedef|import)\b',
            multiLine: true,
          ).hasMatch(source),
          isFalse,
        );
        final exports =
            RegExp(r"export '[^']+'\s+show\s+([^;]+);", dotAll: true)
                .allMatches(source)
                .expand((m) => m[1]!.split(',').map((s) => s.trim()))
                .toList();
        expect(exports.toSet(), catalogPublicNames);
        expect(exports, hasLength(5));
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
