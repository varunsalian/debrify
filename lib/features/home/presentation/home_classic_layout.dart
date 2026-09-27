import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'home_trailer_transitions.dart';

/// Classic board composition with fixed hero geometry and borrowed surfaces.
/// The app shell still owns ambient art behind the board/sidebar. Playback
/// changes the visual signals, never the hero band's size or layer order.
Widget buildHomeClassicLayout({
  required bool isTelevision,
  required double viewportWidth,
  required double Function(double boardHeight) tvHeroBudget,
  required bool trailerActive,
  required ValueListenable<double> takeover,
  required Widget Function(double heroHeight) boardBuilder,
  required Widget Function(double heroHeight) trailerBuilder,
  required Widget Function(double heroHeight) liveBuilder,
  required Widget Function() infoBuilder,
}) => LayoutBuilder(
  builder: (context, constraints) {
    // Budget against available board height, below the header. A fixed band
    // avoids relayout and video refitting on every trailer start/stop frame.
    // Off TV, preserve the original viewport-width breakpoint, not pane width.
    final heroHeight = isTelevision
        ? tvHeroBudget(constraints.maxHeight)
        : (viewportWidth >= 900 ? 300.0 : 196.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        buildHomeTrailerBoardRecede(
          active: trailerActive,
          takeover: takeover,
          board: boardBuilder(heroHeight),
        ),
        // Trailer paints above the board; its owned view handles hit testing.
        if (trailerActive) Positioned.fill(child: trailerBuilder(heroHeight)),
        // Live IPTV occupies the same hero region and wins over the trailer.
        if (trailerActive) Positioned.fill(child: liveBuilder(heroHeight)),
        if (trailerActive) infoBuilder(),
      ],
    );
  },
);
