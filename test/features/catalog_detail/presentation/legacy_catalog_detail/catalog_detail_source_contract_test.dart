import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/catalog_detail_source.dart';

void main() {
  final frozen =
      jsonDecode(
            File(
              'dev/tool/catalog_detail_source_contracts.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final e in frozen.entries) {
    test(
      'S original ${e.key} declaration comments order guards and dispatch',
      () {
        expect(
          catalogCanonicalSource(
            catalogOriginalMember('_CatalogItemDetailScreenState.${e.key}'),
          ),
          catalogCanonicalSource(e.value as String),
        );
      },
    );
  }
  test('S public widget bytes remain identical to formatted ORIGINAL', () {
    final source = File(
      'lib/screens/catalog_item_detail_screen.dart',
    ).readAsStringSync();
    final start = source.indexOf('/// Cinematic detail screen');
    final end = source.indexOf('\nclass _CatalogItemDetailScreenState', start);
    expect(
      source.substring(start, end).trimRight(),
      File(
        'dev/tool/catalog_detail_public_surface.txt',
      ).readAsStringSync().trimRight(),
    );
  });
  test(
    'S lazy fields remain on State and ticker route metadata mixins keep order',
    () {
      final source = File(
        'lib/screens/catalog_item_detail_screen.dart',
      ).readAsStringSync();
      expect(source, contains('late final AnimationController _revealCtrl;'));
      expect(
        source,
        contains('late bool _hasBoundSource = widget.hasBoundSource;'),
      );
      expect(
        RegExp(
          r'with\s+SingleTickerProviderStateMixin,\s+RouteAware,\s+MetadataPresentationMixin<CatalogItemDetailScreen>',
        ).hasMatch(source),
        true,
      );
    },
  );
  test(
    'S rewatch early capability gate and restart are in one declaration',
    () {
      final body = catalogOriginalMember(
        '_CatalogItemDetailScreenState._playPrimary',
      );
      expect(body.indexOf('if (restart == null'), greaterThanOrEqualTo(0));
      expect(
        body.indexOf('if (restart == null'),
        lessThan(body.indexOf('await resetProgressForRewatch')),
      );
      expect(body, contains('restart();'));
      expect(body, isNot(contains('(widget.onRewatch ?? widget.onPlay)()')));
    },
  );
}
