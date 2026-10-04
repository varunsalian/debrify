import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/merged_detail_source.dart';

String canonical(String source) => mergedCanonicalSource(source);

void main() {
  test(
    'public widget fields constructor and documentation stay byte-identical',
    () {
      final source = File(
        'lib/screens/merged_series_detail_screen.dart',
      ).readAsStringSync();
      final start = source.indexOf('/// Merged series page');
      final end = source.indexOf('\nclass _MergedDetailScreenState');
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      expect(
        source.substring(start, end).trimRight(),
        File(
          'dev/tool/merged_detail_public_surface.txt',
        ).readAsStringSync().trimRight(),
      );
    },
  );
  test(
    'source canonicalization preserves literal whitespace and interpolation boundaries',
    () {
      expect(canonical("call( 'two words', )"), canonical("call('two words')"));
      expect(
        canonical("call('two words')"),
        isNot(canonical("call('twowords')")),
      );
      expect(canonical(r"'${name}Suffix'"), isNot(canonical(r"'$nameSuffix'")));
      expect(canonical(r"'${name}'"), canonical(r"'$name'"));
      expect(
        canonical("call(r'two words')"),
        isNot(canonical("call(r'twowords')")),
      );
    },
  );
  final bodies =
      jsonDecode(
            File(
              'dev/tool/merged_detail_source_contracts.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final entry in bodies.entries) {
    test('complete original contract body ${entry.key}', () {
      expect(
        canonical(
          mergedOriginalMember('_MergedDetailScreenState.${entry.key}'),
        ),
        canonical(entry.value as String),
      );
    });
  }
  final lazy =
      jsonDecode(
            File(
              'dev/tool/merged_detail_lazy_originals.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final entry in lazy.entries) {
    test('original lazy declaration and body specification ${entry.key}', () {
      final path = mergedMemberPath('_MergedDetailScreenState.${entry.key}');
      final source = mergedOriginalNames(File(path).readAsStringSync());
      expect(canonical(source), contains(canonical(entry.value as String)));
    });
  }
  test('Xtream route and whole construction preserve ungated handoff', () {
    final source = File(
      'lib/screens/iptv/xtream_series_detail.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> openXtreamSeries(');
    final closing = RegExp(
      r'^}[ \t]*$',
      multiLine: true,
    ).firstMatch(source.substring(start));
    expect(closing, isNotNull);
    final end = start + closing!.end;
    expect(
      source.substring(start, end),
      File(
        'dev/tool/merged_detail_xtream_handoff.txt',
      ).readAsStringSync().trimRight(),
    );
  });
  test(
    'merged slice never constructs or imports append-only source fetching',
    () {
      final files = [
        File('lib/screens/merged_series_detail_screen.dart'),
        if (Directory('lib/features/merged_detail').existsSync())
          ...Directory('lib/features/merged_detail')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
      ];
      for (final file in files) {
        expect(
          file.readAsStringSync(),
          isNot(contains('SeriesSourceFetcher')),
          reason: file.path,
        );
        expect(
          file.readAsStringSync(),
          isNot(contains('mergeSources')),
          reason: file.path,
        );
      }
    },
  );
  test('rewatch and browse have one file with adjacent declarations', () {
    final first = mergedMemberPath('_MergedDetailScreenState._rewatchTitle');
    expect(
      mergedMemberPath('_MergedDetailScreenState._browsePrimarySources'),
      first,
    );
    final source = mergedOriginalNames(File(first).readAsStringSync());
    expect(
      source,
      matches(
        RegExp(r'await restart\(\);\s*}\s*void _browsePrimarySources\(\)'),
      ),
    );
  });
}
