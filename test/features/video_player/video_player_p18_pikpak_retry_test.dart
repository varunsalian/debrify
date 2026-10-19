import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player/widgets/pikpak_retry_overlay.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_player.dart';
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

const _pikpak = 'https://dl.mypikpak.com/cold.mp4';
const _plain = 'https://player.test/warm.mp4';

const _screen = VideoPlayerScreen(
  videoUrl: _pikpak,
  title: 'Cold',
  viewMode: PlaylistViewMode.raw,
  disableAutoResume: true,
  startIndex: 0,
  playlist: [
    PlaylistEntry(url: _pikpak, title: 'cold', provider: 'pikpak'),
    PlaylistEntry(url: _plain, title: 'warm'),
  ],
);

/// Cold-storage fake: PikPak opens never report a duration until [warm].
class _Cold {
  bool warm = false;
  void configure(FakePlayer player) {
    final original = player.onOpen;
    player.onOpen = () {
      final uri =
          (player.state.playlist.medias.isEmpty
                  ? null
                  : player.state.playlist.medias.first)
              ?.uri;
      if (warm || uri != _pikpak) original?.call();
    };
  }
}

int _opensOf(TvEpisodeDriver d, String url) =>
    d.opens.where((m) => m.uri == url).length;

void main() {
  testWidgets(
    'P18 PikPak entry that reports a duration succeeds after one open without the retry banner',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(screen: _screen);
        await d.f.until(
          t,
          () => d.logs.any(
            (l) => l.contains('PikPak: Video metadata loaded successfully'),
          ),
        );
        expect(_opensOf(d, _pikpak), 1);
        expect(find.byType(PikPakRetryOverlay), findsNothing);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 selecting another item cancels an in-flight PikPak cold-storage wait',
    (t) async {
      final cold = _Cold();
      final d = TvEpisodeDriver(t, configurePlayer: cold.configure);
      await d.initialize();
      try {
        await d.mount(screen: _screen, settleInitialization: false);
        expect(_opensOf(d, _pikpak), 1);
        final dynamic next = playerControls(t).onNext!;
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => next()) as Future<dynamic>,
        );
        await d.f.advance(t, const Duration(seconds: 1));
        expect(d.opens.last.uri, _plain);
        expect(
          d.logs.any(
            (l) => l.contains('PikPak: Retry cancelled (token mismatch'),
          ),
          isTrue,
        );
        expect(
          _opensOf(d, _pikpak),
          1,
          reason: 'a cancelled loop never reopens',
        );
        expect(find.byType(PikPakRetryOverlay), findsNothing);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 PikPak first failed attempt shows the retry banner, reopens once and clears on recovery',
    (t) async {
      final cold = _Cold();
      final d = TvEpisodeDriver(t, configurePlayer: cold.configure);
      await d.initialize();
      try {
        await d.mount(screen: _screen, settleInitialization: false);
        // The metadata wait runs on a wall-clock Stopwatch: pump fake time
        // until the first 10 s attempt really elapses (~10 s of real time).
        final watch = Stopwatch()..start();
        while (!d.logs.any((l) => l.contains('PikPak: Retry 1 - reopening')) &&
            watch.elapsed < const Duration(seconds: 40)) {
          await d.f.advance(t, const Duration(milliseconds: 100));
        }
        expect(
          d.logs.any((l) => l.contains('PikPak: Retry 1 - reopening')),
          isTrue,
        );
        await d.f.advance(t, const Duration(milliseconds: 200));
        expect(find.byType(PikPakRetryOverlay), findsOneWidget);
        expect(
          t.widget<PikPakRetryOverlay>(find.byType(PikPakRetryOverlay)).message,
          'Reactivating video...',
        );
        expect(_opensOf(d, _pikpak), 2);
        expect(d.logs.any((l) => l.contains('Monitoring attempt 2/6')), isTrue);
        expect(
          d.logs.any((l) => l.contains('monitoring during delay (2s)')),
          isTrue,
        );
        // The file wakes up during the second attempt's monitoring window.
        cold.warm = true;
        d.player.publishFrame();
        await d.f.until(
          t,
          () => d.logs.any(
            (l) => l.contains('PikPak: Video metadata loaded successfully'),
          ),
        );
        await d.f.advance(t, const Duration(milliseconds: 200));
        expect(find.byType(PikPakRetryOverlay), findsNothing);
        expect(_opensOf(d, _pikpak), 2);
      } finally {
        await d.close();
      }
    },
  );
}
