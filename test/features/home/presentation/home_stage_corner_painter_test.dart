import 'dart:ui';
import 'package:debrify/features/home/presentation/home_stage_corner_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final radius in [0.0, 12.0]) {
    test(
      'radius $radius paints corners without covering the video area',
      () async {
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        HomeStageCornerPainter(
          radius: radius,
          color: const Color(0xFFFF0000),
        ).paint(canvas, const Size(80, 40));
        final picture = recorder.endRecording();
        final image = await picture.toImage(80, 40);
        final data = await image.toByteData(format: ImageByteFormat.rawRgba);
        expect(data, isNotNull);
        int alpha(int x, int y) => data!.getUint8((y * 80 + x) * 4 + 3);
        for (final (x, y) in [(0, 0), (79, 0), (0, 39), (79, 39)]) {
          expect(alpha(x, y), radius == 0 ? 0 : 255);
          if (radius != 0) {
            expect(data!.getUint8((y * 80 + x) * 4), 255);
            expect(data.getUint8((y * 80 + x) * 4 + 1), 0);
          }
        }
        for (final (x, y) in [(40, 20), (40, 0), (40, 39), (0, 20), (79, 20)]) {
          expect(alpha(x, y), 0);
        }
        image.dispose();
        picture.dispose();
      },
    );
  }
}
