import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Extracts a single accent-worthy dominant color from an image, cheaply
/// enough for a weak TV chip:
///
///  * the image is decoded at a tiny size (32px wide) via [ResizeImage], so
///    the pixel pass touches ~1k pixels — microseconds of CPU;
///  * pixels are bucketed on a coarse HSV grid, scored by count × saturation
///    (so a vivid brand color beats a big grey sky), skipping near-black /
///    near-white pixels that say nothing about the artwork;
///  * the winning bucket's average color is normalised into an accent range
///    that reads well on a dark UI (saturation floored, lightness clamped).
///
/// Returns null when the image can't be decoded or nothing colorful survives
/// the filters (e.g. a pure B&W poster) — callers should fall back to the
/// app accent.
Future<ui.Color?> extractDominantColor(ImageProvider provider) async {
  ui.Image? image;
  try {
    image = await _resolveSmall(provider);
    if (image == null) return null;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final bytes = data.buffer.asUint8List();

    // Coarse buckets: 12 hue slots × 3 saturation bands. Tracks per-bucket
    // score and running RGB sums so the winner returns its true average color
    // rather than a quantised approximation.
    final scores = <int, double>{};
    final sumR = <int, int>{}, sumG = <int, int>{}, sumB = <int, int>{};
    final counts = <int, int>{};

    for (int i = 0; i + 3 < bytes.length; i += 4) {
      final a = bytes[i + 3];
      if (a < 128) continue;
      final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
      final hsv = HSVColor.fromColor(ui.Color.fromARGB(255, r, g, b));
      // Too dark / too bright / too grey to be an accent.
      if (hsv.value < 0.16 || hsv.value > 0.97) continue;
      if (hsv.saturation < 0.22) continue;
      final hueSlot = (hsv.hue / 30).floor() % 12;
      final satBand = (hsv.saturation * 3).floor().clamp(0, 2);
      final key = hueSlot * 3 + satBand;
      // Saturated pixels count for more, so a small vivid region can outrank
      // a large washed-out one.
      scores[key] = (scores[key] ?? 0) + 0.35 + hsv.saturation;
      sumR[key] = (sumR[key] ?? 0) + r;
      sumG[key] = (sumG[key] ?? 0) + g;
      sumB[key] = (sumB[key] ?? 0) + b;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    if (scores.isEmpty) return null;

    final best = scores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final n = counts[best]!;
    final avg = ui.Color.fromARGB(
      255,
      sumR[best]! ~/ n,
      sumG[best]! ~/ n,
      sumB[best]! ~/ n,
    );

    // Normalise into a dark-UI accent: keep the hue, ensure it's saturated
    // enough to read as a tint and bright enough to glow on near-black.
    var hsv = HSVColor.fromColor(avg);
    hsv = hsv.withSaturation(hsv.saturation.clamp(0.45, 0.9));
    hsv = hsv.withValue(hsv.value.clamp(0.55, 0.85));
    return hsv.toColor();
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
  }
}

/// Resolves [provider] at a 32px decode and completes with the first frame
/// (or null on error). Uses its own tiny decode so it never forces a large
/// image to be re-decoded at full size.
Future<ui.Image?> _resolveSmall(ImageProvider provider) {
  final completer = Completer<ui.Image?>();
  final stream = ResizeImage(
    provider,
    width: 32,
    policy: ResizeImagePolicy.fit,
  ).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) {
        // Clone: the stream may dispose its copy once listeners detach.
        completer.complete(info.image.clone());
      }
      info.dispose();
      stream.removeListener(listener);
    },
    onError: (error, stack) {
      if (!completer.isCompleted) completer.complete(null);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}
