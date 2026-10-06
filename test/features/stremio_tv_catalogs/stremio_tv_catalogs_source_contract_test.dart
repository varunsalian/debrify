import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../support/stremio_tv_catalogs_source.dart';
import '../../theme/shape_manifest_test.dart' show kShapeResidue;

void ordered(String source, List<String> fragments) {
  var at = 0;
  for (final fragment in fragments) {
    final next = source.indexOf(fragment, at);
    expect(
      next,
      greaterThanOrEqualTo(at),
      reason: 'ordered contract $fragment',
    );
    at = next + fragment.length;
  }
}

void main() {
  test(
    'source reader selects exactly one owner for all manifest declarations',
    () {
      expect(catalogsManifest(), hasLength(19));
      for (final row in catalogsManifest()) {
        expect(catalogsDeclaration(row['original_name']!), isNotEmpty);
      }
    },
  );
  test(
    'frozen reader rejects missing and duplicated owners and reverses only code aliases',
    () {
      final row = catalogsManifest().singleWhere(
        (r) => r['original_name'] == '_ImportUrlDialog',
      );
      final source = catalogsDeclaration('_ImportUrlDialog');
      expect(
        () => catalogsDeclaration('_ImportUrlDialog', sources: {}),
        throwsStateError,
      );
      expect(
        () => catalogsDeclaration(
          '_ImportUrlDialog',
          sources: {catalogsFacade: source, row['destination_file']!: source},
        ),
        throwsStateError,
      );
      expect(
        () => catalogsDeclaration(
          '_ImportUrlDialog',
          sources: {catalogsFacade: '$source\n$source'},
        ),
        throwsStateError,
      );
      expect(
        catalogsDeclaration(
          '_ImportUrlDialog',
          sources: {row['destination_file']!: source},
        ),
        source,
      );
      expect(
        catalogsOriginalNames("LcUrlDialog(); // LcUrlDialog\n'LcUrlDialog'"),
        "_ImportUrlDialog(); // LcUrlDialog\n'LcUrlDialog'",
      );
    },
  );
  test('source guard owned-resource dispose order is frozen', () {
    for (final spec in {
      '_StremioTvLocalCatalogEditorDialogState': [
        '_closeFocusNode.dispose();',
        '_scrollController.dispose();',
        'node.dispose();',
        'super.dispose();',
      ],
      '_StremioTvLocalCatalogsDialogState': [
        '_listScrollController.dispose();',
        '_closeFocusNode.dispose();',
        'n.dispose();',
        'super.dispose();',
      ],
      '_ImportUrlDialogState': [
        '_nameFocusNode.dispose();',
        '_urlFocusNode.dispose();',
        '_cancelFocusNode.dispose();',
        '_importFocusNode.dispose();',
        '_urlController.dispose();',
        '_nameController.dispose();',
        'super.dispose();',
      ],
      '_ImportJsonDialogState': [
        '_nameFocusNode.dispose();',
        '_jsonFocusNode.dispose();',
        '_cancelFocusNode.dispose();',
        '_importFocusNode.dispose();',
        '_jsonController.dispose();',
        '_nameController.dispose();',
        'super.dispose();',
      ],
    }.entries) {
      final source = catalogsDeclaration(spec.key);
      ordered(source.substring(source.indexOf('void dispose()')), spec.value);
    }
  });
  test(
    'source guard labels, scroll timings, PopScope, barrier and HTTP timeout',
    () {
      final editor = catalogsDeclaration(
        '_StremioTvLocalCatalogEditorDialogState',
      );
      expect(editor, contains("debugLabel: 'localCatalogEditorClose'"));
      expect(
        editor,
        contains(
          r"debugLabel: 'localCatalogEditorRemove${_removeFocusNodes.length}'",
        ),
      );
      expect(editor, contains('canPop: false'));
      expect(
        editor,
        contains('ScrollPositionAlignmentPolicy.keepVisibleAtEnd'),
      );
      expect(editor, contains('Duration(milliseconds: 200)'));
      expect(
        catalogsDeclaration('StremioTvLocalCatalogEditorDialog'),
        contains('barrierDismissible: false'),
      );
      final manage = catalogsDeclaration('_StremioTvLocalCatalogsDialogState');
      expect(manage, contains("debugLabel: 'close'"));
      expect(manage, contains(r"debugLabel: 'del${_deleteFocusNodes.length}'"));
      expect(manage, contains('const itemHeight = 56.0;'));
      expect(manage, contains('Duration(milliseconds: 200)'));
      expect(
        catalogsDeclaration('_ImportUrlDialogState'),
        contains('http.get(uri).timeout(const Duration(seconds: 15))'),
      );
      for (final label in ['name', 'url', 'cancel', 'import']) {
        expect(
          catalogsDeclaration('_ImportUrlDialogState'),
          contains("debugLabel: 'stremio-import-url-$label'"),
        );
      }
      for (final label in ['name', 'content', 'cancel', 'import']) {
        expect(
          catalogsDeclaration('_ImportJsonDialogState'),
          contains("debugLabel: 'stremio-import-json-$label'"),
        );
      }
    },
  );
  test(
    'source guard Trakt debugPrint lines and S-only service exception catches',
    () {
      final source = catalogsDeclaration('_ImportTraktDialogState');
      final literals = RegExp(
        r'debugPrint\(\s*([\s\S]*?)\);',
      ).allMatches(source).map((m) => m[1]!.trim()).toList();
      final expected = jsonDecode(
        File('dev/tool/stremio_tv_catalogs_log_lines.json').readAsStringSync(),
      );
      expect(literals, expected);
      for (final name in [
        '_ImportTraktDialogState',
        '_ImportMdblistDialogState',
      ]) {
        final body = catalogsDeclaration(name);
        expect(body, contains("_error = 'Failed to load lists: \$e';"));
        expect(
          RegExp(
            RegExp.escape("_error = 'Failed to import: \$e';"),
          ).allMatches(body),
          hasLength(name == '_ImportTraktDialogState' ? 2 : 1),
        );
      }
      expect(
        catalogsDeclaration('LocalCatalogImporter'),
        contains(
          "if (!kMdblistEnabled) return 'MDBList integration is disabled';",
        ),
      );
    },
  );
  test('shape slice remains four bare radii and six unchanged token calls', () {
    final source = catalogsSource();
    expect(
      RegExp(
        r'BorderRadius\.circular\((\d+)\)',
      ).allMatches(source).map((m) => m[1]),
      ['24', '20', '12', '12'],
    );
    expect(
      RegExp(
        r'app\.shape\.(br(?:Img)?)\((\d+)\)',
      ).allMatches(source).map((m) => '${m[1]}(${m[2]})'),
      ['brImg(10)', 'br(16)', 'br(12)', 'br(12)', 'br(12)', 'br(12)'],
    );
    final floor = kShapeResidue.keys.fold<int>(
      0,
      (count, path) =>
          count +
          RegExp(
            r'app\.shape\.br',
          ).allMatches(File(path).readAsStringSync()).length,
    );
    expect(
      floor,
      488,
      reason: 'the complete shape token floor stays exactly 488',
    );

    expect(
      RegExp(r'BorderRadius\.circular\(\d+\)').allMatches(source),
      hasLength(4),
    );
    expect(RegExp(r'app\.shape\.').allMatches(source), hasLength(6));
    for (final entry in {
      '_StremioTvLocalCatalogEditorDialogState': 1,
      '_StremioTvLocalCatalogsDialogState': 1,
      '_ImportTraktDialogState': 1,
      '_ImportMdblistDialogState': 1,
    }.entries) {
      expect(
        RegExp(
          r'BorderRadius\.circular\(\d+\)',
        ).allMatches(catalogsDeclaration(entry.key)),
        hasLength(entry.value),
      );
    }
    if (catalogsComplete) {
      expect(
        File(catalogsFacade).readAsStringSync(),
        isNot(contains('app.shape.')),
      );
    }
  });

  test('review source guard preserves the masked Trakt source-list reset', () {
    // S: direct-source UI hides _lists; picker sources synchronously clear it
    // again in _fetchLists. Removing this one assignment is behavior-equivalent.
    final source = catalogsDeclaration('_ImportTraktDialogState');
    final start = source.indexOf('Future<void> _onSourceChanged(');
    final end = source.indexOf('Future<void> _fetchLists()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    expect(source.substring(start, end), contains('_lists = [];'));
  });
}
