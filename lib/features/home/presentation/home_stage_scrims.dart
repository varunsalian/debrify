import 'package:flutter/material.dart';

/// The Canvas stage's constant lighting: a left column scrim (identity
/// legibility), a bottom ramp (tabs/shelf legibility) and a bottom-left
/// "text pocket" — a soft radial wash under the identity block. Premium OTT
/// scrims are far heavier than they look (85-95% ink at the text baseline);
/// because the falloff is gradual and in the page's own ink colour it reads
/// as LIGHTING, never as a plate behind the text — bright art (snow, skies,
/// white key art) stays legible without the stage going flat. Painted ABOVE
/// both the idle art and the live video — plain gradient draws over the
/// punch hole, the same on-device-proven pattern as the region feathers.
/// How a stage lights its art. Every variant is a set of CONSTANT gradients
/// painted above the art AND the video — plain draws over the punch hole, the
/// on-device-proven pattern (never an Opacity wrapper, never a tween).
enum HomeStageScrimVariant {
  /// Canvas / Deck / Tonight: left column + bottom ramp + a bottom-left text
  /// pocket, seating an edge-anchored identity block.
  canvas,

  /// Promenade: symmetric — a bottom ramp for the strip, a centred pocket
  /// under the identity, and a light top wash so the trailer pill reads.
  centered,

  /// Atrium: the art is a COLUMN, so the only left lighting it needs is a
  /// narrow feather melting into the ink panel at the seam, plus a bottom
  /// ramp under the poster wall.
  seam,
}

class HomeStageScrims extends StatelessWidget {
  /// Theater mode: ALL the stage lighting fades — the left column scrim, the
  /// bottom ramp and the text pocket exist to seat text and shelf that have
  /// receded, so the video gets the truly clean frame (the logo, gliding to
  /// the top-left corner, carries its own art shadows).
  final bool theater;

  final HomeStageScrimVariant variant;

  const HomeStageScrims({
    super.key,
    this.theater = false,
    this.variant = HomeStageScrimVariant.canvas,
  });

  static const _canvasLayers = <Widget>[
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xF00D0B1A), Color(0xA80D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.32, 0.66],
        ),
      ),
    ),
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF50D0B1A), Color(0xC20D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.20, 0.50],
        ),
      ),
    ),
    // The text pocket: centred under the identity block (lower-left
    // quadrant), dissolving well before mid-screen so the art/video
    // keeps its glow everywhere else.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.72, 0.55),
          radius: 0.95,
          colors: [Color(0xCC0D0B1A), Color(0x000D0B1A)],
          stops: [0.12, 1.0],
        ),
      ),
    ),
  ];

  static const _centeredLayers = <Widget>[
    // Bottom ramp — deeper than Canvas's: the strip sits lower and the
    // identity stands directly on it.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF70D0B1A), Color(0xCC0D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.24, 0.56],
        ),
      ),
    ),
    // Centre pocket: the symmetric twin of Canvas's corner pocket, seating
    // the centred logo + meta without flattening the frame's edges.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, 0.30),
          radius: 0.78,
          colors: [Color(0xB80D0B1A), Color(0x000D0B1A)],
          stops: [0.10, 1.0],
        ),
      ),
    ),
    // A whisper at the top so the TRAILER pill never sits on bright sky.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x730D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.22],
        ),
      ),
    ),
  ];

  static const _seamLayers = <Widget>[
    // The seam: a narrow melt into the ink panel on the left. Short, so the
    // art keeps its width — the panel beside it already carries the text.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xF20D0B1A), Color(0x8C0D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.07, 0.22],
        ),
      ),
    ),
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF50D0B1A), Color(0xCC0D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.36, 0.76],
        ),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final layers = switch (variant) {
      HomeStageScrimVariant.canvas => _canvasLayers,
      HomeStageScrimVariant.centered => _centeredLayers,
      HomeStageScrimVariant.seam => _seamLayers,
    };
    return AnimatedOpacity(
      opacity: theater ? 0.0 : 1.0,
      duration: theater
          ? const Duration(milliseconds: 900)
          : const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: Stack(fit: StackFit.expand, children: layers),
    );
  }
}
