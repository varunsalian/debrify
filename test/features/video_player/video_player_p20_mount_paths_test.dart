import 'package:debrify/services/player_display_controls.dart';
import 'dart:convert';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;

import 'support/video_player_environment.dart';

/// Plain fixture mounts outside any error-capturing zone: a startup branch
/// that never creates, readies or opens its player fails the shared mount's
/// own expectations directly.
final _live = IptvChannel(
  name: 'P20 mount live',
  url: 'https://mount.test/live.ts',
  contentType: 'live',
  group: 'News',
);

final _paths = <String, VideoPlayerScreen>{
  'single file': const VideoPlayerScreen(
    videoUrl: 'https://mount.test/single.mp4',
    title: 'P20 mount single',
  ),
  'series pack': const VideoPlayerScreen(
    videoUrl: 'https://mount.test/s1e1.mkv',
    title: 'P20 Mount Show',
    contentType: 'series',
    playlist: [
      PlaylistEntry(
        url: 'https://mount.test/s1e1.mkv',
        title: 'P20.Mount.Show.S01E01.mkv',
      ),
      PlaylistEntry(
        url: 'https://mount.test/s1e2.mkv',
        title: 'P20.Mount.Show.S01E02.mkv',
      ),
    ],
  ),
  'collection': const VideoPlayerScreen(
    videoUrl: 'https://mount.test/c0.mkv',
    title: 'P20 mount collection',
    contentType: 'movie',
    playlist: [
      PlaylistEntry(url: 'https://mount.test/c0.mkv', title: 'C0.mkv'),
      PlaylistEntry(url: 'https://mount.test/c1.mkv', title: 'C1.mkv'),
    ],
  ),
  'live channel': VideoPlayerScreen(
    videoUrl: _live.url,
    title: _live.name,
    iptvChannels: [_live],
    iptvStartIndex: 0,
  ),
  'Stremio TV slot': const VideoPlayerScreen(
    videoUrl: 'https://mount.test/slot.mp4',
    title: 'P20 mount slot',
    startAtPercent: .5,
    stremioTvChannels: [
      {'id': 'slot', 'name': 'P20 slot'},
    ],
    stremioTvCurrentChannelId: 'slot',
  ),
  'external audio': const VideoPlayerScreen(
    videoUrl: 'https://mount.test/video.mp4',
    title: 'P20 mount audio',
    audioUrl: 'https://mount.test/audio.m4a',
  ),
  'PikPak link': const VideoPlayerScreen(
    videoUrl: 'https://dl.mypikpak.com/p20-mount.mp4',
    title: 'P20 mount PikPak',
  ),
};

final _wakeDrain = Object();

void main() {
  for (final native in [false, true]) {
    for (final entry in _paths.entries) {
      testWidgets(
        'P20 mount ${entry.key} native=$native creates one player and opens the launch media',
        (t) async {
          final f = VideoPlayerEnvironment(native: native);
          await t.runAsync(f.initialize);
          try {
            await f.mount(t, entry.value);
            expect(f.players, hasLength(1));
            final opens = [
              for (final c in f.player.calls)
                if (c.$1 == 'open')
                  ((c.$2 as (mk.Playable, bool)).$1 as mk.Media).uri,
            ];
            expect(opens.take(1), [
              entry.value.playlist?.first.url ?? entry.value.videoUrl,
            ]);
            await f.actions.settle(t);
          } finally {
            await f.close(t);
            // Leave the shared wakelock queue cursor in the real zone (as
            // EngineDriver.close does) so later cases in this isolate do not stall.
            await t.runAsync(
              () => PlayerDisplayControls.instance.setWakelockOwner(
                _wakeDrain,
                false,
              ),
            );
          }
        },
      );
    }
  }

  testWidgets(
    'P20 mount a lazy entry whose first resolve fails reloads it paused through the playlist',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      var served = 0;
      try {
        await f.finish<void>(t, TorboxStorage.saveTorboxApiKey('tb-key'));
        f.network.handler = (r) {
          if (!r.url.path.endsWith('/torrents/requestdl')) {
            return http.Response('{}', 404);
          }
          return served++ == 0
              ? http.Response('{}', 500)
              : http.Response(
                  jsonEncode({
                    'success': true,
                    'data': 'https://cdn.test/m.mkv',
                  }),
                  200,
                );
        };
        await f.mount(
          t,
          const VideoPlayerScreen(
            videoUrl: '',
            title: 'P20 mount lazy',
            disableAutoResume: true,
            playlist: [
              PlaylistEntry(
                url: '',
                title: 'Lazy.Mount.mkv',
                provider: 'torbox',
                torboxTorrentId: 41,
                torboxFileId: 7,
              ),
            ],
          ),
        );
        final opens = [
          for (final c in f.player.calls)
            if (c.$1 == 'open') (c.$2 as (mk.Playable, bool)),
        ];
        expect(opens.map((o) => (o.$1 as mk.Media).uri), [
          'https://cdn.test/m.mkv',
        ]);
        expect(opens.map((o) => o.$2), [false]);
        await f.actions.settle(t);
      } finally {
        await f.close(t);
        await t.runAsync(
          () => PlayerDisplayControls.instance.setWakelockOwner(
            _wakeDrain,
            false,
          ),
        );
      }
    },
  );
}
