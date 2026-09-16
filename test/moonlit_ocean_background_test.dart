import 'dart:ui' as ui;

import 'package:debrify/widgets/home/moonlit_ocean_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ocean TV clock is bounded and pauses for reduced motion', (
    tester,
  ) async {
    Widget host({bool reduced = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: const MoonlitOceanBackground(lowPower: true),
      ),
    );
    await tester.pumpWidget(host());
    final finder = find.descendant(
      of: find.byType(MoonlitOceanBackground),
      matching: find.byType(CustomPaint),
    );
    final painter = tester.widget<CustomPaint>(finder).painter!;
    var repaints = 0;
    void changed() => repaints++;
    painter.addListener(changed);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
    expect(repaints, inInclusiveRange(29, 31));
    await tester.pumpWidget(host(reduced: true));
    await tester.pump();
    final stopped = repaints;
    await tester.pump(const Duration(seconds: 2));
    expect(repaints, stopped);
    expect(tester.binding.transientCallbackCount, 0);
    painter.removeListener(changed);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('compiled ocean shader moves water while keeping moon still', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final program = await ui.FragmentProgram.fromAsset(
        'assets/shaders/moonlit_ocean.frag',
      );
      final shader = program.fragmentShader();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      // A textured source makes displacement directly measurable.
      for (var y = 0; y < 160; y++) {
        for (var x = 0; x < 280; x++) {
          canvas.drawRect(
            Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
            Paint()
              ..color = Color.fromARGB(
                255,
                (x * 7) % 256,
                (y * 11) % 256,
                (x + y) % 256,
              ),
          );
        }
      }
      final sourcePicture = recorder.endRecording();
      final image = await sourcePicture.toImage(280, 160);
      sourcePicture.dispose();
      shader
        ..setFloat(1, 280)
        ..setFloat(2, 160)
        ..setFloat(3, 1.75)
        ..setImageSampler(0, image);
      Future<List<int>> frame(double time) async {
        shader.setFloat(0, time);
        final r = ui.PictureRecorder();
        Canvas(r).drawRect(
          const Rect.fromLTWH(0, 0, 280, 160),
          Paint()..shader = shader,
        );
        final picture = r.endRecording();
        final rendered = await picture.toImage(280, 160);
        final bytes = (await rendered.toByteData())!.buffer
            .asUint8List()
            .toList();
        rendered.dispose();
        picture.dispose();
        return bytes;
      }

      final a = await frame(0), b = await frame(3);
      var changedWater = 0;
      for (var y = 100; y < 150; y++) {
        for (var x = 20; x < 260; x++) {
          final i = (y * 280 + x) * 4;
          if (a[i] != b[i] || a[i + 1] != b[i + 1]) changedWater++;
        }
      }
      expect(changedWater, greaterThan(3000));
      final moon = (26 * 280 + 190) * 4;
      expect(a.sublist(moon, moon + 4), b.sublist(moon, moon + 4));
      shader.dispose();
      image.dispose();
    });
  });
}
