import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_player.dart';
import 'support/tv_episode_driver.dart';

final _live = IptvChannel(
  name: 'Wait live',
  url: 'https://wait.test/live.ts',
  contentType: 'live',
  channelNumber: 1,
);

/// Opens never report a duration on their own; the test publishes it.
void _silent(FakePlayer player) => player.onOpen = () {};

/// A wait's first 100 ms poll marks its start (t0).
DateTime _waitStart(TvEpisodeDriver d, String wait) {
  final polls = d.timers.where(
    (x) =>
        x.duration == const Duration(milliseconds: 100) &&
        x.stack.contains(wait),
  );
  expect(polls, isNotEmpty, reason: '$wait polls every 100 ms');
  return polls.first.at;
}

Future<void> _publishAt(
  TvEpisodeDriver d,
  Duration offset, {
  String wait = 'waitForVideoReady',
}) async {
  // A later wait (resume) only starts once the earlier ready wait ends.
  for (
    var i = 0;
    i < 200 && !d.timers.any((x) => x.stack.contains(wait));
    i++
  ) {
    await d.f.advance(d.t, const Duration(milliseconds: 100));
  }
  final t0 = _waitStart(d, wait);
  while (d.t.binding.clock.now().difference(t0) < offset) {
    await d.f.advance(d.t, const Duration(milliseconds: 10));
  }
  d.player.publishFrame();
  await d.f.advance(d.t, const Duration(seconds: 1));
}

void main() {
  for (final (label, at, seeks) in [
    // 100 polls 100 ms apart, then one more duration read when the wait ends
    // at 10.0 s: a duration published before then still drives the start.
    ('inside the 10 s window still applies the percent start', 9950, true),
    ('after the 10 s window gives up on the percent start', 10050, false),
  ]) {
    testWidgets('P18 a duration arriving ${at}ms after open $label', (t) async {
      final d = TvEpisodeDriver(t, configurePlayer: _silent);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _live.url,
            title: _live.name,
            iptvChannels: [_live],
            startAtPercent: 0.5,
          ),
          settleInitialization: false,
        );
        final before = d.seeks.length;
        await _publishAt(d, Duration(milliseconds: at));
        expect(
          d.seeks.skip(before).contains(const Duration(minutes: 10)),
          seeks,
        );
      } finally {
        await d.close();
      }
    });
  }

  testWidgets(
    'P18 a duration arriving early is waited for, then the percent start applies',
    (t) async {
      final d = TvEpisodeDriver(t, configurePlayer: _silent);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _live.url,
            title: _live.name,
            iptvChannels: [_live],
            startAtPercent: 0.5,
          ),
          settleInitialization: false,
        );
        final before = d.seeks.length;
        expect(d.seeks.length, before, reason: 'nothing seeks before duration');
        await _publishAt(d, const Duration(seconds: 3));
        expect(d.seeks.skip(before), contains(const Duration(minutes: 10)));
      } finally {
        await d.close();
      }
    },
  );
}
