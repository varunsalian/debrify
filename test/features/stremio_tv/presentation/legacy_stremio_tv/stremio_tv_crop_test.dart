import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/stremio_tv_goldens.dart';

void main() {
  testWidgets(
    'C3 (R) crop helper captures the requested subrectangle at DPR two',
    (t) async {
      const key = ValueKey('synthetic-boundary');
      await t.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 100,
                height: 80,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: Colors.red)),
                    Positioned(
                      left: 20,
                      top: 10,
                      width: 40,
                      height: 30,
                      child: ColoredBox(color: Color(0xFF0000FF)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final image = await t.runAsync(
        () => stremioTvCropBoundary(
          boundary,
          const Rect.fromLTWH(20, 10, 40, 30),
          pixelRatio: 2,
        ),
      );
      expect(image!.width, 80);
      expect(image.height, 60);
      final pixels = await t.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      final bytes = pixels!.buffer.asUint8List();
      for (var offset = 0; offset < bytes.length; offset += 4) {
        expect(
          bytes.sublist(offset, offset + 4),
          [0, 0, 255, 255],
          reason: 'crop excludes the red boundary surrounding the blue region',
        );
      }
      image.dispose();
    },
  );
}
