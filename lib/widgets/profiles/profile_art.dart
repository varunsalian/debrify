import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'profile_face_art.dart';

/// A built-in avatar, either drawn in code or shipped as a bounded asset.
///
/// The original abstract set is gradients and keyframes, so it costs only a
/// few KB of code. Character art can opt into a small bundled GIF instead.
/// Both forms have no network or cache dependency and survive tvOS reclaiming
/// its Caches.
///
/// Each entry declares its own wash colour, so the gate never decodes anything
/// to paint its backdrop.
@immutable
class ProfileArt {
  final String id;
  final String label;

  /// The gate's ambient wash for this art. Declared, never sampled.
  final Color color;

  /// Whether [paint] uses its `t`. Static art skips the ticker entirely.
  final bool animated;

  /// Paints into a [size] box. `t` runs 0→1 and wraps; it is only advanced
  /// while the avatar is focused.
  final void Function(Canvas canvas, Size size, double t)? paint;

  /// Bundled raster animation. Mutually exclusive with [paint].
  final String? assetPath;

  const ProfileArt({
    required this.id,
    required this.label,
    required this.color,
    required this.animated,
    required this.paint,
  }) : assetPath = null;

  const ProfileArt.asset({
    required this.id,
    required this.label,
    required this.color,
    required this.assetPath,
    this.animated = true,
  }) : paint = null;

  bool get isAsset => assetPath != null;
}

class ProfileArtRegistry {
  ProfileArtRegistry._();

  static ProfileArt? byId(String id) {
    for (final art in all) {
      if (art.id == id) return art;
    }
    return null;
  }

  static const List<ProfileArt> all = <ProfileArt>[
    ProfileArt.asset(
      id: 'snack_popcorn',
      label: 'Popcorn Panic',
      color: Color(0xFFD5292F),
      assetPath: 'assets/images/profile_avatars/snack_popcorn.gif',
    ),
    ProfileArt.asset(
      id: 'snack_soda',
      label: 'Soda Star',
      color: Color(0xFF149B9E),
      assetPath: 'assets/images/profile_avatars/snack_soda.gif',
    ),
    ProfileArt.asset(
      id: 'snack_nacho',
      label: 'Nacho Mood',
      color: Color(0xFFD99012),
      assetPath: 'assets/images/profile_avatars/snack_nacho.gif',
    ),
    ProfileArt.asset(
      id: 'snack_gummy',
      label: 'Gummy Gamer',
      color: Color(0xFF8625B5),
      assetPath: 'assets/images/profile_avatars/snack_gummy.gif',
    ),
    ProfileArt.asset(
      id: 'snack_sundae',
      label: 'Sleepy Sundae',
      color: Color(0xFF5DAE9F),
      assetPath: 'assets/images/profile_avatars/snack_sundae.gif',
    ),
    // Flat-vector characters, drawn in code. Deliberately unshaded — see
    // ProfileFaceArt. Each blinks once per cycle, which is the whole of their
    // animation.
    ProfileArt(
      id: 'cat',
      label: 'Mittens',
      color: Color(0xFF1F6F63),
      animated: true,
      paint: ProfileFaceArt.cat,
    ),
    ProfileArt(
      id: 'fox',
      label: 'Fox',
      color: Color(0xFFB4552C),
      animated: true,
      paint: ProfileFaceArt.fox,
    ),
    ProfileArt(
      id: 'panda',
      label: 'Panda',
      color: Color(0xFF3C6E8F),
      animated: true,
      paint: ProfileFaceArt.panda,
    ),
    ProfileArt(
      id: 'owl',
      label: 'Owl',
      color: Color(0xFF6B4E8E),
      animated: true,
      paint: ProfileFaceArt.owl,
    ),
    ProfileArt(
      id: 'bear',
      label: 'Bear',
      color: Color(0xFF8A5A33),
      animated: true,
      paint: ProfileFaceArt.bear,
    ),
    ProfileArt(
      id: 'kiddo',
      label: 'Kiddo',
      color: Color(0xFFC77E3A),
      animated: true,
      paint: ProfileFaceArt.kiddo,
    ),
    ProfileArt(
      id: 'grownup',
      label: 'Grown-up',
      color: Color(0xFF3E7A6B),
      animated: true,
      paint: ProfileFaceArt.grownup,
    ),
    ProfileArt(
      id: 'sage',
      label: 'Sage',
      color: Color(0xFF5C6B8A),
      animated: true,
      paint: ProfileFaceArt.sage,
    ),
    ProfileArt(
      id: 'ghost',
      label: 'Boo',
      color: Color(0xFF4C3F8F),
      animated: true,
      paint: ProfileFaceArt.ghost,
    ),
    ProfileArt(
      id: 'blob',
      label: 'Blob',
      color: Color(0xFF2E6B4F),
      animated: true,
      paint: ProfileFaceArt.blob,
    ),
    ProfileArt(
      id: 'aurora',
      label: 'Aurora',
      color: Color(0xFF1E8E7E),
      animated: true,
      paint: _aurora,
    ),
    ProfileArt(
      id: 'ember',
      label: 'Ember',
      color: Color(0xFFE2563D),
      animated: true,
      paint: _ember,
    ),
    ProfileArt(
      id: 'tide',
      label: 'Tide',
      color: Color(0xFF3D7BE2),
      animated: true,
      paint: _tide,
    ),
    ProfileArt(
      id: 'prism',
      label: 'Prism',
      color: Color(0xFF8B5BE2),
      animated: true,
      paint: _prism,
    ),
    ProfileArt(
      id: 'dusk',
      label: 'Dusk',
      color: Color(0xFF5B3DA8),
      animated: false,
      paint: _dusk,
    ),
    ProfileArt(
      id: 'moss',
      label: 'Moss',
      color: Color(0xFF3D8B5B),
      animated: false,
      paint: _moss,
    ),
    ProfileArt(
      id: 'sand',
      label: 'Sand',
      color: Color(0xFFC98F4A),
      animated: false,
      paint: _sand,
    ),
    ProfileArt(
      id: 'slate',
      label: 'Slate',
      color: Color(0xFF4A5A72),
      animated: false,
      paint: _slate,
    ),
  ];

  // ── painters ──────────────────────────────────────────────────────────────

  static void _fill(Canvas canvas, Size size, List<Color> colors) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ).createShader(rect),
    );
  }

  /// A soft blob of light. Screen-blended so overlaps brighten rather than
  /// muddy, which is what keeps these reading as light and not as paint.
  static void _bloom(
    Canvas canvas,
    Size size,
    Offset center,
    double radius,
    Color color,
  ) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = RadialGradient(
          colors: <Color>[color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  static void _aurora(Canvas canvas, Size size, double t) {
    _fill(canvas, size, const <Color>[Color(0xFF0A1F2E), Color(0xFF10333F)]);
    final sweep = math.sin(t * 2 * math.pi);
    _bloom(
      canvas,
      size,
      Offset(size.width * (0.32 + sweep * 0.16), size.height * 0.38),
      size.width * 0.62,
      const Color(0xFF1E8E7E),
    );
    _bloom(
      canvas,
      size,
      Offset(size.width * (0.72 - sweep * 0.14), size.height * 0.66),
      size.width * 0.5,
      const Color(0xFF7BD9A8),
    );
  }

  static void _ember(Canvas canvas, Size size, double t) {
    _fill(canvas, size, const <Color>[Color(0xFF2B0F14), Color(0xFF160A10)]);
    final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    _bloom(
      canvas,
      size,
      Offset(size.width * 0.5, size.height * 0.58),
      size.width * (0.46 + pulse * 0.14),
      const Color(0xFFE2563D),
    );
    _bloom(
      canvas,
      size,
      Offset(size.width * 0.62, size.height * 0.34),
      size.width * 0.34,
      const Color(0xFFF4B860),
    );
  }

  static void _tide(Canvas canvas, Size size, double t) {
    _fill(canvas, size, const <Color>[Color(0xFF0B1B33), Color(0xFF11294D)]);
    final paint = Paint()
      ..blendMode = BlendMode.screen
      ..color = const Color(0xFF3D7BE2).withValues(alpha: 0.55);
    for (var band = 0; band < 3; band++) {
      final path = Path();
      final phase = t * 2 * math.pi + band * 0.9;
      final baseline = size.height * (0.52 + band * 0.13);
      path.moveTo(0, size.height);
      path.lineTo(0, baseline);
      for (var x = 0.0; x <= size.width; x += size.width / 24) {
        final y =
            baseline +
            math.sin(phase + x / size.width * 2.6) * size.height * 0.045;
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.close();
      canvas.drawPath(path, paint..color = paint.color.withValues(alpha: 0.28));
    }
    _bloom(
      canvas,
      size,
      Offset(size.width * 0.5, size.height * 0.28),
      size.width * 0.5,
      const Color(0xFF6FA8FF),
    );
  }

  static void _prism(Canvas canvas, Size size, double t) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: 2 * math.pi,
          transform: GradientRotation(t * 2 * math.pi),
          colors: const <Color>[
            Color(0xFFE23D4C),
            Color(0xFFF4B860),
            Color(0xFF39D98A),
            Color(0xFF5B8CFF),
            Color(0xFF8B5BE2),
            Color(0xFFE23D4C),
          ],
        ).createShader(rect),
    );
    // Knock the saturation back so a face-sized tile is not a strobe.
    canvas.drawRect(rect, Paint()..color = const Color(0x33101828));
  }

  static void _dusk(Canvas canvas, Size size, double t) {
    _fill(canvas, size, const <Color>[Color(0xFF2A1A52), Color(0xFF120C24)]);
    _bloom(
      canvas,
      size,
      Offset(size.width * 0.34, size.height * 0.3),
      size.width * 0.6,
      const Color(0xFF5B3DA8),
    );
    _bloom(
      canvas,
      size,
      Offset(size.width * 0.74, size.height * 0.72),
      size.width * 0.44,
      const Color(0xFFB14BE8),
    );
  }

  static void _moss(Canvas canvas, Size size, double t) {
    _fill(canvas, size, const <Color>[Color(0xFF15291C), Color(0xFF0B160F)]);
    _bloom(
      canvas,
      size,
      Offset(size.width * 0.4, size.height * 0.42),
      size.width * 0.58,
      const Color(0xFF3D8B5B),
    );
    _bloom(
      canvas,
      size,
      Offset(size.width * 0.72, size.height * 0.24),
      size.width * 0.36,
      const Color(0xFF9BD98A),
    );
  }

  static void _sand(Canvas canvas, Size size, double t) {
    _fill(canvas, size, const <Color>[Color(0xFF3A2616), Color(0xFF1E140C)]);
    _bloom(
      canvas,
      size,
      Offset(size.width * 0.46, size.height * 0.5),
      size.width * 0.58,
      const Color(0xFFC98F4A),
    );
    _bloom(
      canvas,
      size,
      Offset(size.width * 0.68, size.height * 0.28),
      size.width * 0.32,
      const Color(0xFFF4D8A8),
    );
  }

  static void _slate(Canvas canvas, Size size, double t) {
    _fill(canvas, size, const <Color>[Color(0xFF2A3550), Color(0xFF141B29)]);
    _bloom(
      canvas,
      size,
      Offset(size.width * 0.36, size.height * 0.34),
      size.width * 0.54,
      const Color(0xFF4A5A72),
    );
  }
}
