import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

/// Settles the poster rows back while the ambient trailer plays, so the
/// moving picture owns the frame (Nuvio/Netflix behavior) and any DPAD move
/// brings them straight back. Implemented as a flat bg-tinted VEIL fading in
/// ABOVE the rows — NOT an Opacity around them: fading the rows subtree
/// meant a rows-viewport-sized saveLayer re-rastered on every frame of the
/// fade (the "trailer start stutters" kind of cost on a weak TV GPU), while
/// this is one solid fill that paints nothing at all when idle. Rows live
/// BELOW the hero band, so the veil can never sit over the trailer
/// underlay's punch-through hole.
Widget buildHomeTrailerRowsDim({
  required bool active,
  required ValueListenable<bool> showing,
  required Widget rows,
}) {
  if (!active) return rows;
  return Stack(
    fit: StackFit.passthrough,
    children: [
      rows,
      Positioned.fill(
        child: IgnorePointer(
          child: ValueListenableBuilder<bool>(
            valueListenable: showing,
            builder: (context, on, _) => AnimatedOpacity(
              opacity: on ? 1.0 : 0.0,
              // LIGHTS OFF, asymmetric: the theatre dims slowly when the
              // picture starts, but any DPAD move brings the room back
              // FAST so navigation never feels gated by an effect.
              duration: on
                  ? const Duration(milliseconds: 900)
                  : const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              // Near-black: the rows become ghosts (a whisper of structure
              // stays so pressing DOWN isn't a leap into a void), graded a
              // touch deeper toward the screen's foot.
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xE00D0B1A), Color(0xFA0D0B1A)],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// Fades the board UI fully OUT as the trailer takes over — cards, rows and
/// hero block leave the stage entirely (the compact info overlay replaces
/// them). GPU-frugal by design:
///  • the wrapper tree shape is FIXED (Opacity always present), so the
///    board subtree — focus nodes, list scroll state — is never re-parented
///    when the takeover starts/ends;
///  • Opacity is layer-free at 1.0 and paints nothing at all at 0.0; the
///    brief mid-fade is over static content (raster-cache friendly);
///  • a TickerMode freezes the hidden board's animators (skeleton shimmers)
///    so nothing re-records an invisible subtree per frame.
/// A short follower tween smooths the driving value, so the instant kill
/// (focus moved → takeover snaps to 0) eases the board back in ~240ms
/// instead of popping. Focus stays on the hidden card: any arrow restores
/// the board, and SELECT opens the very title being showcased.
Widget buildHomeTrailerBoardRecede({
  required bool active,
  required ValueListenable<double> takeover,
  required Widget board,
}) {
  if (!active) return board;
  return ValueListenableBuilder<double>(
    valueListenable: takeover,
    child: board,
    builder: (context, target, child) {
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(end: target),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        child: child,
        builder: (context, t, kid) {
          final tt = t.clamp(0.0, 1.0);
          return Opacity(
            opacity: 1.0 - tt,
            child: TickerMode(enabled: tt < 0.95, child: kid!),
          );
        },
      );
    },
  );
}
