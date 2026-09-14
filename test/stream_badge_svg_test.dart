import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/models/stream_badge_rules.dart';
import 'package:debrify/services/stream_badge_matcher.dart';
import 'package:debrify/services/stream_badges_service.dart';
import 'package:debrify/services/stream_badge_svg_image.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/stream_badge_svg.dart';
import 'package:debrify/widgets/source_row.dart';
import 'package:debrify/widgets/stream_badge_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _svg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20"><rect width="100" height="20" fill="#ff0000"/></svg>';
const _stylesheetColour =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20"><style>.red { fill: #ff0000; }</style><rect class="red" width="100" height="20"/></svg>';
const _dashedSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20"><path d="M0 10H100" stroke="red" stroke-dasharray="0.001 0.001"/></svg>';
const _markerPoints = '0,0 1,1 2,0 3,1 4,0 5,1';
String _markerChain() {
  final markers = [
    for (var i = 0; i < 7; i++)
      '<marker id="m$i"><polyline points="$_markerPoints"${i < 6 ? ' marker-mid="url(#m${i + 1})"' : ''}/></marker>',
  ].join();
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20"><defs>$markers</defs><polyline points="$_markerPoints" marker-mid="url(#m0)"/></svg>';
}

const _inheritedMarkerCycle =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20" marker-mid="url(#m)"><defs><marker id="m"><polyline points="$_markerPoints"/></marker></defs><polyline points="$_markerPoints"/></svg>';
Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

String _maskChain(int count) {
  final masks = [
    for (var i = 0; i < count; i++)
      '<mask id="m$i"><rect width="100" height="20" fill="white"${i + 1 < count ? ' mask="url(#m${i + 1})"' : ''}/></mask>',
  ].join();
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20"><defs>$masks</defs><rect width="100" height="20" fill="red" mask="url(#m0)"/></svg>';
}

const _stylesheetCycle =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20"><style>.loop { clip-path: url(#c); }</style><defs><clipPath id="c" class="loop"><rect width="100" height="20"/></clipPath></defs><rect width="100" height="20" clip-path="url(#c)"/></svg>';

Future<ImageInfo> _resolve(ImageProvider provider) {
  final result = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, _) {
      result.complete(image);
      stream.removeListener(listener);
    },
    onError: (Object error, StackTrace? stack) {
      result.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return result.future;
}

void main() {
  test(
    'rejects dash expansion in attributes and inherited inline declarations',
    () {
      for (final input in [
        _dashedSvg,
        _dashedSvg.replaceFirst(
          'stroke-dasharray="0.001 0.001"',
          'style="stroke-dasharray: 0.001 0.001"',
        ),
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20" stroke-dasharray="0.001 0.001"><path d="M0 10H100" stroke="red"/></svg>',
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20"><g style="stroke: red; stroke-dasharray: 0.001 0.001"><path d="M0 10H100" stroke-dasharray="inherit"/></g></svg>',
        _dashedSvg.replaceFirst(
          'stroke-dasharray="0.001 0.001"',
          'style="stroke-da/**/sharray: 0.001 0.001"',
        ),
        _dashedSvg.replaceFirst(
          'stroke-dasharray="0.001 0.001"',
          'style="stroke-dasharray: 1e-8,1e-8; stroke-dasharray: none"',
        ),
      ]) {
        expect(() => validateBadgeSvg(_bytes(input)), throwsFormatException);
      }
    },
  );
  test('rejects per-vertex marker expansion and inherited marker cycles', () {
    for (final input in [_markerChain(), _inheritedMarkerCycle]) {
      expect(() => validateBadgeSvg(_bytes(input)), throwsFormatException);
    }
  });
  testWidgets(
    'stylesheet artwork fails decoding instead of rendering incorrect colours',
    (tester) async {
      addTearDown(() {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      });
      final provider = StreamBadgeSvgImage(
        'https://host/styles.svg',
        maxWidth: 150,
        maxHeight: 30,
        loadBytes: (_) async => _bytes(_stylesheetColour),
      );
      await tester.runAsync(() async {
        await expectLater(
          _resolve(provider).then((image) => image.dispose()),
          throwsFormatException,
        );
      });
    },
  );
  for (final (kind, svg) in [
    ('stylesheet', _stylesheetColour),
    ('dash', _dashedSvg),
  ]) {
    testWidgets('rejected $kind artwork displays the production text fallback', (
      tester,
    ) async {
      final url = 'https://host/$kind-fallback.svg';
      // Isolate work and its completion signals must use real async time, not
      // the widget test's fake clock.
      final (bytes, completed) = (await tester.runAsync(
        () async => (Completer<Uint8List>(), Completer<Object?>()),
      ))!;
      final provider = StreamBadgeSvgImage(
        url,
        maxWidth: 420,
        maxHeight: 48,
        loadBytes: (_) => bytes.future,
      );
      // Start decoding in real async time, as the validator uses an isolate.
      final stream = (await tester.runAsync(
        () async => provider.resolve(ImageConfiguration.empty),
      ))!;
      final listener = ImageStreamListener(
        (image, _) {
          image.dispose();
          completed.complete(null);
        },
        onError: (Object error, StackTrace? _) {
          completed.complete(error);
        },
      );
      stream.addListener(listener);
      // Feed the production chip the same real decoding request, without HTTP.
      PaintingBinding.instance.imageCache.putIfAbsent(
        StreamBadgeSvgImage(url, maxWidth: 420, maxHeight: 48),
        () => stream.completer!,
      );
      addTearDown(() {
        stream.removeListener(listener);
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StreamBadgeChip(
              height: 20,
              rule: StreamBadgeRule(
                id: kind,
                groupId: '',
                name: 'BADGE',
                pattern: '.',
                imageUrl: url,
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        bytes.complete(_bytes(svg));
        expect(
          await completed.future.timeout(const Duration(seconds: 10)),
          isA<FormatException>(),
        );
      });
      await tester.pumpAndSettle();
      expect(find.text('BADGE'), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('explicit dash none retains solid stroke rendering', (
    tester,
  ) async {
    addTearDown(() {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
    for (final declaration in [
      'stroke-dasharray="none"',
      'style="stroke-dasharray: none"',
    ]) {
      final svg = _dashedSvg
          .replaceFirst('stroke-dasharray="0.001 0.001"', declaration)
          .replaceFirst('stroke="red"', 'stroke="red" stroke-width="2"');
      expect(
        validateBadgeSvg(_bytes(svg)),
        contains('stroke-dasharray="none"'),
      );
      final provider = StreamBadgeSvgImage(
        'https://host/solid.svg',
        maxWidth: 150,
        maxHeight: 30,
        loadBytes: (_) async => _bytes(svg),
      );
      final image = (await tester.runAsync(() => _resolve(provider)))!;
      try {
        final pixels = await tester.runAsync(
          () => image.image.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        expect(
          pixels!.getUint32((15 * image.image.width + 75) * 4),
          0xff0000ff,
        );
        expect(pixels.getUint32(0), 0);
      } finally {
        image.dispose();
      }
    }
  });
  testWidgets(
    'inline SVG colours render correctly through the bitmap provider',
    (tester) async {
      addTearDown(() {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      });
      final provider = StreamBadgeSvgImage(
        'https://host/inline.svg',
        maxWidth: 150,
        maxHeight: 30,
        loadBytes: (_) async => _bytes(
          _svg.replaceFirst('fill="#ff0000"', 'style="fill: #00ff00"'),
        ),
      );
      final image = await tester.runAsync(() => _resolve(provider));
      try {
        final pixels = await tester.runAsync(
          () => image!.image.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        expect(pixels!.getUint32(0), 0x00ff00ff);
      } finally {
        image?.dispose();
      }
    },
  );
  test(
    'SVG URL routing handles query strings and preserves bitmap failures',
    () {
      expect(isBadgeSvgUrl('https://host/LOGO.SVG?token=x#tag'), true);
      expect(isBadgeSvgUrl('https://host/image.png?file=logo.svg'), false);
      expect(isBadgeBitmapUrl('https://host/LOGO.PNG?token=x'), true);
      expect(isBadgeBitmapUrl('https://host/badge/4k'), false);
    },
  );
  test('static gradients, clips, metadata and UTF-8 remain supported', () {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="20"><title>Qualité</title><defs><linearGradient id="g"><stop stop-color="red"/></linearGradient><clipPath id="c"><rect width="10" height="10"/></clipPath></defs><path fill="url(#g)" clip-path="url(\'#c\')" d="M0 0h10v10z"/></svg>';
    final normalized = validateBadgeSvg(_bytes(svg));
    expect(normalized, contains('Qualité'));
    expect(normalized, contains('clip-path="url(#c)"'));
  });
  for (final body in [
    '<script>alert(1)</script>',
    '<image href="https://host/x.png"/>',
    '<use href="#x"/>',
    '<pattern id="x"/>',
    '<filter id="x"/>',
    '<animate attributeName="x"/>',
    '<foreignObject/>',
    '<path onload="evil()"/>',
    '<path fill="url(https://host/x)"/>',
    '<style>@import "https://host/a.css";</style>',
    '<linearGradient id="a" href="#b"/><linearGradient id="b" href="#a"/>',
    '<mask id="a"><path mask="url(#a)"/></mask>',
  ]) {
    test('rejects unsupported SVG: $body', () {
      expect(
        () => validateBadgeSvg(_bytes('<svg>$body</svg>')),
        throwsFormatException,
      );
    });
  }
  for (final svg in [
    '<!DOCTYPE svg [<!ENTITY x SYSTEM "file:///etc/passwd">]><svg>&x;</svg>',
    '<html/>',
    '<svg>',
    '<svg>${'<g>' * 34}${'</g>' * 34}</svg>',
    '<svg>${'<path/>' * 2048}</svg>',
    '<svg>${' ' * maxBadgeSvgBytes}</svg>',
  ]) {
    test('rejects invalid or oversized document (${svg.length} bytes)', () {
      expect(() => validateBadgeSvg(_bytes(svg)), throwsA(isA<Exception>()));
    });
  }

  test('network service bounds bytes even without Content-Length', () async {
    final client = MockClient.streaming(
      (request, body) async => http.StreamedResponse(
        Stream.fromIterable([
          List.filled(maxBadgeSvgBytes, 0),
          [0],
        ]),
        200,
      ),
    );
    final service = BadgeSvgFileService(clientFactory: () => client);
    expect(service.concurrentFetches, 4);
    await expectLater(
      service.get('https://host/badge.svg'),
      throwsFormatException,
    );
  });
  test('rejects exponential reference expansion without requiring a cycle', () {
    final masks = [
      for (var i = 0; i < 12; i++)
        '<mask id="m$i"><path mask="url(#m${i + 1})"/><path mask="url(#m${i + 1})"/></mask>',
    ].join();
    expect(
      () => validateBadgeSvg(
        _bytes('<svg><defs>$masks<mask id="m12"><path/></mask></defs></svg>'),
      ),
      throwsFormatException,
    );
  });
  test('rejects linear mask chains with multiplicative render cost', () {
    expect(
      () => validateBadgeSvg(_bytes(_maskChain(30))),
      throwsFormatException,
    );
  });
  test('counts repeated mask uses on elements without ids', () {
    final repeated = _maskChain(7).replaceFirst(
      '</svg>',
      '${'<rect width="100" height="20" mask="url(#m0)"/>' * 20}</svg>',
    );
    expect(() => validateBadgeSvg(_bytes(repeated)), throwsFormatException);
  });
  test('rejects obfuscated stylesheet references and owned inline cycles', () {
    for (final reference in [
      "URL( '#c' )",
      'u/**/rl(#c)',
      r'u\72l(#c)',
      'url(/**/#c)',
    ]) {
      final input = _stylesheetCycle.replaceAll(
        'clip-path: url(#c)',
        'clip-path: $reference',
      );
      expect(() => validateBadgeSvg(_bytes(input)), throwsFormatException);
    }
    final inlineCycle = _stylesheetCycle
        .replaceFirst('<style>.loop { clip-path: url(#c); }</style>', '')
        .replaceFirst('class="loop"', 'style="clip-path: u/**/rl(#c)"');
    expect(() => validateBadgeSvg(_bytes(inlineCycle)), throwsFormatException);
    final cssMask = _maskChain(
      2,
    ).replaceFirst('<defs>', '<style>rect { mask: url(#m0); }</style><defs>');
    expect(() => validateBadgeSvg(_bytes(cssMask)), throwsFormatException);
  });
  test('simple masks, inline colours and clips remain supported', () {
    for (final input in [
      _maskChain(2),
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20"><defs><clipPath id="c"><rect width="100" height="20"/></clipPath></defs><rect width="100" height="20" style="fill: #ff0000; clip-path: url(#c)"/></svg>',
    ]) {
      final normalized = validateBadgeSvg(_bytes(input));
      expect(validateBadgeSvg(_bytes(normalized)), normalized);
      expect(normalized, isNot(contains('style=')));
    }
  });
  test(
    'rejects stylesheet references without assigning them to style ancestors',
    () {
      expect(
        () => validateBadgeSvg(_bytes(_stylesheetCycle)),
        throwsFormatException,
      );
    },
  );
  test(
    'network service times out stalled headers and closes its client',
    () async {
      final client = _StalledClient();
      final service = BadgeSvgFileService(
        clientFactory: () => client,
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        service.get('https://host/badge.svg'),
        throwsA(isA<TimeoutException>()),
      );
      expect(client.closed, true);
    },
  );
  test(
    'network service times out stalled response bodies as well as headers',
    () async {
      final body = StreamController<List<int>>();
      final service = BadgeSvgFileService(
        clientFactory: () => MockClient.streaming(
          (_, __) async => http.StreamedResponse(body.stream, 200),
        ),
        timeout: const Duration(milliseconds: 20),
      );
      try {
        await expectLater(
          service.get('https://host/badge.svg'),
          throwsA(isA<TimeoutException>()),
        );
      } finally {
        await body.close();
      }
    },
  );
  test(
    'network service retains revalidation headers and safe response metadata',
    () async {
      final service = BadgeSvgFileService(
        clientFactory: () => MockClient((request) async {
          expect(request.headers['if-none-match'], 'v1');
          return http.Response(
            _svg,
            200,
            headers: {'etag': 'v2', 'cache-control': 'max-age=60'},
          );
        }),
      );
      final response = await service.get(
        'https://host/badge.svg',
        headers: {'If-None-Match': 'v1'},
      );
      expect(response.eTag, 'v2');
      expect(response.fileExtension, '.svg');
      expect(
        await response.content.expand((chunk) => chunk).toList(),
        _bytes(_svg),
      );
    },
  );

  testWidgets(
    'SVGs rasterize to bounded coloured images and share the image cache',
    (tester) async {
      addTearDown(() {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      });
      var loads = 0;
      Future<Uint8List> load(String _) async {
        loads++;
        return _bytes(_svg);
      }

      final provider = StreamBadgeSvgImage(
        'https://host/badge.svg',
        maxWidth: 210,
        maxHeight: 30,
        loadBytes: load,
      );
      final images = await tester.runAsync(
        () => Future.wait([_resolve(provider), _resolve(provider)]),
      );
      expect(loads, 1);
      expect(images!.first.image.width, 150);
      expect(images.first.image.height, 30);
      final rgba = await tester.runAsync(
        () => images.first.image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      expect(rgba!.getUint32(0), 0xff0000ff);
      final again = await tester.runAsync(() => _resolve(provider));
      expect(loads, 1);
      again!.dispose();
      for (final image in images) {
        image.dispose();
      }
    },
  );

  testWidgets(
    'malformed SVG failure can retry and does not poison the bitmap cache',
    (tester) async {
      addTearDown(() {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      });
      var attempts = 0;
      Future<Uint8List> load(String _) async =>
          _bytes(++attempts == 1 ? '<html/>' : _svg);
      final provider = StreamBadgeSvgImage(
        'https://host/retry.svg',
        maxWidth: 150,
        maxHeight: 30,
        loadBytes: load,
      );
      await tester.runAsync(() async {
        await expectLater(_resolve(provider), throwsA(isA<Exception>()));
      });
      await tester.pump();
      final image = await tester.runAsync(() => _resolve(provider));
      expect(attempts, 2);
      expect(image!.image.width, 150);
      image.dispose();
    },
  );

  testWidgets('TV source focus retains the hydrated SVG widget and bitmap', (
    tester,
  ) async {
    const url = 'https://host/focus.svg';
    final seed = StreamBadgeSvgImage(
      url,
      maxWidth: 546,
      maxHeight: 66,
      loadBytes: (_) async => _bytes(_svg),
    );
    final image = await tester.runAsync(() => _resolve(seed));
    const key = StreamBadgeSvgImage(url, maxWidth: 546, maxHeight: 66);
    PaintingBinding.instance.imageCache.putIfAbsent(
      key,
      () => OneFrameImageStreamCompleter(Future.value(image!)),
    );
    final service = StreamBadgesService.instance;
    service.resetProfileScope();
    final matcher = StreamBadgeMatcher([
      StreamBadgeRuleset(
        groups: const [],
        rules: [
          StreamBadgeRule(
            id: 'svg',
            groupId: '',
            name: 'SVG',
            pattern: 'Movie',
            imageUrl: url,
          ),
        ],
      ),
    ]);
    service.matcher.value = matcher;
    await tester.runAsync(() => matcher.matchesFor(name: 'Movie'));
    final row = FocusNode();
    final sibling = FocusNode();
    addTearDown(() {
      row.dispose();
      sibling.dispose();
      service.resetProfileScope();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: Scaffold(
            body: Column(
              children: [
                Focus(focusNode: sibling, child: const SizedBox(height: 10)),
                SourceRow(
                  title: 'Source',
                  subtitle: 'metadata',
                  badgeName: 'Movie',
                  focusNode: row,
                  onTap: () {},
                  isTelevision: true,
                  showPlayPill: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final svgImage = find.byWidgetPredicate(
      (w) => w is Image && w.image is StreamBadgeSvgImage,
    );
    expect(svgImage, findsOneWidget);
    final widget = tester.widget<Image>(svgImage);
    final pixels = find.descendant(
      of: svgImage,
      matching: find.byType(RawImage),
    );
    final bitmap = tester.widget<RawImage>(pixels).image;
    expect(bitmap, isNotNull);
    final geometry = tester.getSize(find.byType(SourceRow));
    for (var i = 0; i < 8; i++) {
      (i.isEven ? row : sibling).requestFocus();
      await tester.pumpAndSettle();
      expect(identical(tester.widget(svgImage), widget), true);
      expect(tester.widget<RawImage>(pixels).image, same(bitmap));
      expect(tester.getSize(find.byType(SourceRow)), geometry);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'mixed SVG/PNG badges keep PNG loading and SVG fallback styling',
    (tester) async {
      // Seed the production provider key so the real chip can render offline.
      const url = 'https://host/mark.SVG?raw=true';
      final seed = StreamBadgeSvgImage(
        url,
        maxWidth: 420,
        maxHeight: 48,
        loadBytes: (_) async => _bytes(_svg),
      );
      final image = await tester.runAsync(() => _resolve(seed));
      const key = StreamBadgeSvgImage(url, maxWidth: 420, maxHeight: 48);
      PaintingBinding.instance.imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(Future.value(image!)),
      );
      addTearDown(() {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      });
      final rules = [
        StreamBadgeRule(
          id: 'svg',
          groupId: '',
          name: 'SVG',
          pattern: '.',
          imageUrl: url,
          tagColor: Colors.black,
        ),
        StreamBadgeRule(
          id: 'png',
          groupId: '',
          name: 'PNG',
          pattern: '.',
          imageUrl: 'https://host/image.png',
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StreamBadgeStrip(badges: rules, height: 20)),
        ),
      );
      await tester.pump();
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      final svgImage = find.byWidgetPredicate(
        (w) => w is Image && w.image is StreamBadgeSvgImage,
      );
      expect(svgImage, findsOneWidget);
      final widget = tester.widget<Image>(svgImage);
      final fallback =
          widget.errorBuilder!(
                tester.element(svgImage),
                Exception('bad SVG'),
                null,
              )
              as Align;
      expect((fallback.child as Text).data, 'SVG');
      expect((fallback.child as Text).style!.color, Colors.white);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _StalledClient extends http.BaseClient {
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
  @override
  void close() {
    closed = true;
  }
}
