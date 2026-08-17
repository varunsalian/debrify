import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The 43-byte 1×1 transparent GIF87a — a real, decodable animation.
final Uint8List tinyGif = Uint8List.fromList(<int>[
  0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, //
  0x01, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00,
  0xFF, 0xFF, 0xFF, 0x21, 0xF9, 0x04, 0x01, 0x00,
  0x00, 0x00, 0x00, 0x2C, 0x00, 0x00, 0x00, 0x00,
  0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x02, 0x44,
  0x01, 0x00, 0x3B,
]);

/// A real PNG, painted rather than hand-rolled, so the decoder sees genuine
/// image data at a known size and colour.
Future<Uint8List> paintPng({
  required int size,
  Color color = const Color(0xFF3366CC),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = color,
  );
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
