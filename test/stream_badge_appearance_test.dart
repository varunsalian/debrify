import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/models/stream_badge_rules.dart';
import 'package:debrify/utils/stream_badge_appearance.dart';
import 'package:debrify/widgets/stream_badge_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

StreamBadgeRule rule(Map<String, Object?> values) =>
    StreamBadgeRule.fromJson({'name': '4K', 'pattern': '4k', ...values})!;

void main() {
  test('preset styles and contrast-safe labels reach native TV unchanged', () {
    for (final style in ['filled', 'outlined', 'filled and bordered']) {
      final r = rule({
        'imageURL': 'https://example.invalid/4k.png',
        'tagColor': '#FFBE01',
        'textColor': '#FFBE01',
        'borderColor': '#00FF00',
        'tagStyle': style,
      });
      final appearance = StreamBadgeAppearance(r);
      final filled = style != 'outlined';
      expect(
        appearance.background,
        filled ? const Color(0xFFFFBE01) : StreamBadgeAppearance.darkBacking,
      );
      expect(
        appearance.foreground,
        filled ? Colors.black : const Color(0xFFFFBE01),
      );
      expect(
        appearance.border,
        style == 'filled' ? null : const Color(0xFF00FF00),
      );
      expect(appearance.nativeBadge(r), {
        'label': '4K',
        'imageUrl': r.imageUrl,
        'fillColor': appearance.background.toARGB32(),
        'textColor': appearance.foreground.toARGB32(),
        'borderColor': appearance.outline.toARGB32(),
      });
    }
  });

  test('transparent artwork backgrounds and label fallbacks stay readable', () {
    final dark = StreamBadgeAppearance(rule({'tagColor': '#00000000'}));
    expect(dark.background, StreamBadgeAppearance.darkBacking);
    expect(dark.foreground, Colors.white);
    final white = StreamBadgeAppearance(rule({'tagColor': '#FFFFFF'}));
    expect(white.foreground, Colors.black);
    final translucent = StreamBadgeAppearance(
      rule({'tagColor': '#80FFFFFF', 'textColor': '#10FFFFFF'}),
    );
    expect(translucent.background.a, 1);
    expect(translucent.foreground, Colors.black);
    final colored = StreamBadgeAppearance(rule({'textColor': '#00FF00'}));
    expect(colored.foreground, const Color(0xFF00FF00));
  });

  for (final fixture in [
    (ink: Colors.black, fill: '#FFBE01', background: const Color(0xFFFFBE01)),
    (
      ink: Colors.white,
      fill: '#00000000',
      background: StreamBadgeAppearance.darkBacking,
    ),
    (ink: const Color(0xFF007A15), fill: '#FFFFFF', background: Colors.white),
  ]) {
    for (final rowColor in [const Color(0xFF171321), Colors.white]) {
      testWidgets(
        'loaded ${fixture.ink} artwork keeps its pixels and fill on $rowColor',
        (tester) async {
          // Seed the real image cache with artwork on a transparent canvas.
          // This exercises CachedNetworkImage's loaded path without HTTP or disk.
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawRect(
            const Rect.fromLTWH(4, 4, 24, 8),
            Paint()..color = fixture.ink,
          );
          final picture = recorder.endRecording();
          final artwork = await tester.runAsync(() => picture.toImage(32, 16));
          picture.dispose();
          const url = 'https://example.invalid/black-artwork.png';
          final provider = ResizeImage.resizeIfNeeded(
            null,
            48,
            const CachedNetworkImageProvider(url),
          );
          final imageKey = await provider.obtainKey(ImageConfiguration.empty);
          PaintingBinding.instance.imageCache.putIfAbsent(
            imageKey,
            () => OneFrameImageStreamCompleter(
              Future.value(ImageInfo(image: artwork!)),
            ),
          );
          final boundaryKey = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                backgroundColor: rowColor,
                body: Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: StreamBadgeChip(
                      height: 20,
                      rule: rule({
                        'imageURL': url,
                        'tagColor': fixture.fill,
                        'textColor': '#FFBE01',
                      }),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final rendered = (await tester.runAsync(() => boundary.toImage()))!;
          final pixels = (await tester.runAsync(
            () => rendered.toByteData(format: ui.ImageByteFormat.rawRgba),
          ))!;
          Color pixel(int x, int y) {
            final offset = (y * rendered.width + x) * 4;
            return Color.fromARGB(
              pixels.getUint8(offset + 3),
              pixels.getUint8(offset),
              pixels.getUint8(offset + 1),
              pixels.getUint8(offset + 2),
            );
          }

          expect(pixel(2, rendered.height ~/ 2), fixture.background);
          expect(pixel(rendered.width ~/ 2, rendered.height ~/ 2), fixture.ink);
          rendered.dispose();
          await tester.pumpWidget(const SizedBox());
          PaintingBinding.instance.imageCache.clear();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'image placeholders and failed artwork use readable fallback text',
    (tester) async {
      final r = rule({
        'imageURL': 'https://example.invalid/missing.png',
        'tagColor': '#FFFFFF',
        'textColor': '#FFFFFF',
        'tagStyle': 'filled and bordered',
        'borderColor': '#FFBE01',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: StreamBadgeChip(rule: r)),
        ),
      );
      final cached = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      final context = tester.element(find.byType(CachedNetworkImage));
      for (final label in [
        cached.placeholder!(context, r.imageUrl!),
        cached.errorWidget!(context, r.imageUrl!, Exception('offline')),
      ]) {
        expect(label, isA<Align>());
        expect(((label as Align).child! as Text).style!.color, Colors.black);
      }
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(StreamBadgeChip),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((box.decoration as BoxDecoration).color, Colors.white);
      expect(
        (box.decoration as BoxDecoration).border!.top.color,
        const Color(0xFFFFBE01),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
