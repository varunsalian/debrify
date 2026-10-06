import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Render the route layer, then crop the transformed logical sheet bounds.
/// The original sheet owns no boundary; this adds no production widget node.
Future<ui.Image> stremioTvCropBoundary(
  RenderRepaintBoundary boundary,
  Rect logicalBounds, {
  double pixelRatio = 1,
}) async {
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final source = Rect.fromLTWH(
    logicalBounds.left * pixelRatio,
    logicalBounds.top * pixelRatio,
    logicalBounds.width * pixelRatio,
    logicalBounds.height * pixelRatio,
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    image,
    source,
    Rect.fromLTWH(0, 0, source.width, source.height),
    Paint(),
  );
  final picture = recorder.endRecording();
  final cropped = await picture.toImage(
    source.width.ceil(),
    source.height.ceil(),
  );
  picture.dispose();
  image.dispose();
  return cropped;
}

Future<ui.Image> stremioTvPickerImage(WidgetTester tester) async {
  final sheet = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_ManualSourcePickerSheet',
  );
  expect(sheet, findsOneWidget);
  final element = sheet.evaluate().single;
  final box = element.findRenderObject()! as RenderBox;
  Element? boundaryElement;
  element.visitAncestorElements((ancestor) {
    if (ancestor.renderObject is RenderRepaintBoundary) {
      boundaryElement = ancestor;
      return false;
    }
    return true;
  });
  expect(
    boundaryElement,
    isNotNull,
    reason: 'Modal route owns a repaint boundary',
  );
  final captured = find.byElementPredicate(
    (e) => identical(e, boundaryElement),
  );
  expect(
    find.descendant(
      of: captured,
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'StremioTvTuner',
      ),
    ),
    findsNothing,
    reason: 'Picker region boundary excludes the tuner',
  );
  final boundary = boundaryElement!.renderObject! as RenderRepaintBoundary;
  final bounds = MatrixUtils.transformRect(
    box.getTransformTo(boundary),
    Offset.zero & box.size,
  );
  expect(bounds.width, greaterThan(0));
  expect(bounds.height, greaterThan(0));
  return stremioTvCropBoundary(boundary, bounds);
}
