import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:debrify/utils/stream_badge_svg.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  final fixtures =
      jsonDecode(
            File(
              'test/fixtures/stream_badge_svg_contract.json',
            ).readAsStringSync(),
          )
          as List<dynamic>;
  for (final fixture in fixtures.cast<Map<String, dynamic>>()) {
    testWidgets('shared SVG contract: ${fixture['name']}', (tester) async {
      final svg =
          '<svg xmlns="http://www.w3.org/2000/svg" '
          'viewBox="0 0 100 20" ${fixture['root'] ?? ''}>'
          '${fixture['body']}</svg>';
      final bytes = Uint8List.fromList(utf8.encode(svg));
      if (fixture['accept'] != true) {
        expect(() => validateBadgeSvg(bytes), throwsA(isA<Exception>()));
        return;
      }
      final normalized = validateBadgeSvg(bytes);
      expect(
        XmlDocument.parse(normalized).descendants
            .whereType<XmlElement>()
            .expand((element) => element.attributes)
            .where((attribute) => attribute.name.local == 'style'),
        isEmpty,
      );
      expect(
        validateBadgeSvg(Uint8List.fromList(utf8.encode(normalized))),
        normalized,
      );
      await tester.runAsync(() async {
        // Exercise the actual compiler, not just acceptance. The comment-dash
        // reproduction used to expand a tiny fixture into 900 KB here.
        final loader = SvgStringLoader(normalized);
        final compiled = await loader.loadBytes(null);
        expect(compiled.lengthInBytes, lessThan(4096));
        final picture = await vg.loadPicture(loader, null);
        try {
          final image = await picture.picture.toImage(100, 20);
          try {
            final pixels = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            expect(
              pixels!.getUint32((10 * 100 + 50) * 4),
              int.parse(fixture['pixel'] as String, radix: 16),
            );
          } finally {
            image.dispose();
          }
        } finally {
          picture.picture.dispose();
        }
      });
    });
  }
  test('deep XML is rejected before building its tree', () {
    for (final depth in [100, 5000, 15000]) {
      final svg = '<svg>${'<g>' * depth}${'</g>' * depth}</svg>';
      expect(
        () => validateBadgeSvg(Uint8List.fromList(utf8.encode(svg))),
        throwsFormatException,
      );
    }
  });
  test('mask expansion budget includes geometry, not just XML node count', () {
    final path = 'M0 0${'L1 1' * 4000}';
    final masks = [
      for (var i = 0; i < 5; i++)
        '<mask id="m$i"><path d="$path"${i < 4 ? ' mask="url(#m${i + 1})"' : ''}/></mask>',
    ].join();
    final svg = '<svg><defs>$masks</defs><path mask="url(#m0)"/></svg>';
    expect(svg.length, lessThan(maxBadgeSvgBytes));
    expect(
      () => validateBadgeSvg(Uint8List.fromList(utf8.encode(svg))),
      throwsFormatException,
    );
  });
}
