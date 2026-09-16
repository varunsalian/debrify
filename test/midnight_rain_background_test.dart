import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:debrify/widgets/home/midnight_rain_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TV rain keeps full depth with a bounded paint cadence', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: MidnightRainBackground(lowPower: true)),
    );
    final painter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(MidnightRainBackground),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    var repaints = 0;
    void changed() => repaints++;
    painter.addListener(changed);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
    expect(repaints, inInclusiveRange(29, 31));
    final canvas = _RainCanvas();
    painter.paint(canvas, const Size(960, 540));
    expect(canvas.batches, lessThanOrEqualTo(4));
    expect(
      canvas.streaks,
      greaterThanOrEqualTo(420),
      reason: 'Keep the full scene on TV rather than reducing density',
    );
    expect(
      canvas.widths.toSet().length,
      greaterThanOrEqualTo(3),
      reason: 'Foreground and distant rain retain distinct depths',
    );
    expect(canvas.finite, isTrue);
    painter.removeListener(changed);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}

class _RainCanvas extends Fake implements Canvas {
  int batches = 0;
  int streaks = 0;
  bool finite = true;
  final widths = <double>[];

  @override
  void drawRawPoints(ui.PointMode mode, Float32List points, Paint paint) {
    expect(mode, ui.PointMode.lines);
    batches++;
    streaks += points.length ~/ 4;
    finite = finite && points.every((value) => value.isFinite);
    widths.add(paint.strokeWidth);
  }

  @override
  void drawOval(Rect rect, Paint paint) {}
  @override
  void drawRect(Rect rect, Paint paint) {}
  @override
  void save() {}
  @override
  void restore() {}
  @override
  void translate(double dx, double dy) {}
}
