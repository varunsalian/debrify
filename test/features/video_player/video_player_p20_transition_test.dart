import 'package:debrify/screens/video_player/widgets/transition_overlay.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/engine_driver.dart';
import 'support/player_actions.dart';

const _a = 'https://transition.test/a.mp4';
const _b = 'https://transition.test/b.mp4';

/// Debrify TV: Next asks the provider for the following item and runs the
/// transition overlay, which the play listener ends.
final _screen = VideoPlayerScreen(
  videoUrl: _a,
  title: 'P20 transition',
  requestMagicNext: () async => {'url': _b, 'title': 'P20 next'},
);

bool _opened(EngineDriver d, String url) => d.player.calls.any(
  (c) =>
      c.$1 == 'open' &&
      ((c.$2 as (mk.Playable, bool)).$1 as mk.Media).uri == url,
);

/// Presses Next and returns once the incoming media has opened (its play
/// edge is the open's own `playing=true`).
Future<void> _next(EngineDriver d) async {
  d.observe(playerControls(d.t).onNext!);
  await d.f.until(d.t, () => _opened(d, _b));
}

void main() {
  testWidgets(
    'P20 the transition overlay ends three seconds after the incoming play edge',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await d.mount(screen: _screen);
        await _next(d);
        expect(find.byType(TransitionOverlay), findsOneWidget);
        await d.f.advance(t, const Duration(milliseconds: 2900));
        expect(find.byType(TransitionOverlay), findsOneWidget);
        await d.f.advance(t, const Duration(milliseconds: 200));
        expect(find.byType(TransitionOverlay), findsNothing);
        await d.f.actions.settle(t);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a second play edge during the transition restarts its three-second window',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await d.mount(screen: _screen);
        await _next(d);
        await d.f.advance(t, const Duration(milliseconds: 1000));
        d.player.emit('playing', false);
        d.player.emit('playing', true);
        await d.f.advance(t, const Duration(milliseconds: 2500));
        expect(find.byType(TransitionOverlay), findsOneWidget);
        await d.f.advance(t, const Duration(milliseconds: 600));
        expect(find.byType(TransitionOverlay), findsNothing);
        await d.f.actions.settle(t);
      } finally {
        await d.close();
      }
    },
  );
}
