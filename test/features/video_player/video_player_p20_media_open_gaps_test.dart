import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/engine_driver.dart';
import 'support/fake_player.dart';
import 'support/pip_lifecycle_driver.dart';
import 'support/video_player_environment.dart';

const _a = PlaylistEntry(url: 'https://open-gaps.test/a.mp4', title: 'Gap A');
const _b = PlaylistEntry(url: 'https://open-gaps.test/b.mp4', title: 'Gap B');
const _playlist = VideoPlayerScreen(
  videoUrl: 'https://open-gaps.test/a.mp4',
  title: 'P20 open gaps',
  disableAutoResume: true,
  startIndex: 0,
  playlist: [_a, _b],
);

void main() {
  for (final ios in [true, false]) {
    testWidgets(
      'P20 an open during ${ios ? 'iOS' : 'Android'} PiP resets sub-visibility to ${ios ? 'yes' : 'no'}',
      (t) async {
        final seq = <String>[];
        final f = VideoPlayerEnvironment(
          native: true,
          configurePlayer: (p) {
            p.beforeOperation = (name, value) {
              if (name == 'open') seq.add('open');
            };
            (p.platform! as FakeNativePlayer).beforeOperation = (name, value) {
              if (name != 'setProperty') return;
              final (key, v) = value as (String, String);
              if (key == 'sub-visibility') seq.add(v);
            };
          },
        );
        final d = PipLifecycleDriver(t, f, ios: ios);
        await d.initialize();
        try {
          await d.mount(_playlist);
          await d.enter();
          await d.deliver('onPipModeChanged', true);
          seq.clear();
          f.player.emit('completed', true);
          await f.until(t, () => seq.contains('open'));
          expect(seq.take(seq.indexOf('open') + 1).toList(), [
            ios ? 'yes' : 'no',
            'open',
          ]);
          await d.deliver('onPipModeChanged', false);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets('P20 Standard tuning logs no tuning diagnostics at all', (
    t,
  ) async {
    final d = EngineDriver(t);
    await d.initialize();
    try {
      await d.mount();
      expect(
        d.logs.where((l) => l.startsWith('Player: network tuning')),
        isEmpty,
      );
    } finally {
      await d.close();
    }
  });
}
