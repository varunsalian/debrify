import 'dart:convert';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

/// TVMaze knows the show (official name) and only episode 1's title.
http.Response? _partialTvmaze(http.Request r) {
  if (r.url.host != 'api.tvmaze.com') return null;
  if (r.url.path.endsWith('/episodes')) {
    return http.Response(
      jsonEncode([
        {'id': 1, 'season': 1, 'number': 1, 'name': 'Opening'},
      ]),
      200,
    );
  }
  return http.Response(
    jsonEncode({
      'id': 91,
      'name': 'Branch Show',
      'externals': {'imdb': 'tt9100001'},
      'genres': <String>[],
    }),
    200,
  );
}

Future<TvEpisodeDriver> _start(
  WidgetTester t,
  VideoPlayerScreen screen, {
  bool tv = false,
  http.Response? Function(http.Request)? network,
}) async {
  final d = TvEpisodeDriver(t);
  await d.initialize();
  if (tv) PlatformUtil.debugSetAndroidTvCached(true);
  await d.f.finish(t, TVMazeService.clearCache());
  d.f.network.handler = (r) => network?.call(r) ?? http.Response('{}', 404);
  await d.mount(screen: screen);
  return d;
}

TvControls _tv(WidgetTester t) => t.widget<TvControls>(find.byType(TvControls));

IptvChannel _iptv(int n, {String? group}) => IptvChannel(
  name: 'Branch channel $n',
  url: 'https://branch.test/$n.ts',
  contentType: 'vod',
  group: group,
  channelNumber: n,
);

void main() {
  testWidgets(
    'P18 a TVMaze show without this episode titles "Show — Episode N", marked clean',
    (t) async {
      final d = await _start(
        t,
        const VideoPlayerScreen(
          videoUrl: 'https://player.test/b2.mp4',
          title: 'Branch.S01E02.mkv',
          contentImdbId: 'tt9100001',
          disableAutoResume: true,
          startIndex: 1,
          playlist: [
            PlaylistEntry(
              url: 'https://player.test/b1.mp4',
              title: 'Branch.S01E01.mkv',
            ),
            PlaylistEntry(
              url: 'https://player.test/b2.mp4',
              title: 'Branch.S01E02.mkv',
            ),
          ],
        ),
        tv: true,
        network: _partialTvmaze,
      );
      try {
        await d.f.until(
          t,
          () => _tv(t).title == 'Branch Show — Episode 2',
          reason: 'TVMaze show name without an episode title',
        );
        expect(_tv(t).titleIsClean, isTrue);
        expect(_tv(t).subtitle, 'Season 1, Episode 2');
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P18 a TVMaze episode title is marked clean on the TV dock', (
    t,
  ) async {
    final d = await _start(
      t,
      const VideoPlayerScreen(
        videoUrl: 'https://player.test/b1.mp4',
        title: 'Branch.S01E01.mkv',
        contentImdbId: 'tt9100001',
        disableAutoResume: true,
        startIndex: 0,
        playlist: [
          PlaylistEntry(
            url: 'https://player.test/b1.mp4',
            title: 'Branch.S01E01.mkv',
          ),
          PlaylistEntry(
            url: 'https://player.test/b2.mp4',
            title: 'Branch.S01E02.mkv',
          ),
        ],
      ),
      tv: true,
      network: _partialTvmaze,
    );
    try {
      await d.f.until(t, () => _tv(t).title == 'Branch Show — Opening');
      expect(_tv(t).titleIsClean, isTrue);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P18 a pack episode without TVMaze data is a clean "Episode N" on the TV dock',
    (t) async {
      final d = await _start(
        t,
        const VideoPlayerScreen(
          videoUrl: 'https://player.test/q1.mp4',
          title: 'Quiet.S03E04.mkv',
          disableAutoResume: true,
          startIndex: 0,
          playlist: [
            PlaylistEntry(
              url: 'https://player.test/q1.mp4',
              title: 'Quiet.S03E04.mkv',
            ),
            PlaylistEntry(
              url: 'https://player.test/q2.mp4',
              title: 'Quiet.S03E05.mkv',
            ),
          ],
        ),
        tv: true,
      );
      try {
        expect(_tv(t).title, 'Episode 4');
        expect(_tv(t).titleIsClean, isTrue);
        expect(_tv(t).subtitle, 'quiet • Season 3, Episode 4');
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P18 a catalog singleton title is marked clean on the TV dock', (
    t,
  ) async {
    final d = await _start(
      t,
      const VideoPlayerScreen(
        videoUrl: 'https://player.test/one.mp4',
        title: 'Mangled.Release.S02E03.mkv',
        contentTitle: 'Clean Show',
        contentType: 'series',
        playlist: [
          PlaylistEntry(
            url: 'https://player.test/one.mp4',
            title: 'Mangled.Release.S02E03.mkv',
          ),
        ],
      ),
      tv: true,
    );
    try {
      expect(_tv(t).title, 'Clean Show');
      expect(_tv(t).titleIsClean, isTrue);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P18 a content title never replaces entry titles in a multi-item collection',
    (t) async {
      final d = await _start(
        t,
        const VideoPlayerScreen(
          videoUrl: 'https://player.test/c1.mp4',
          title: 'Collection',
          contentTitle: 'Catalog Name',
          contentType: 'movie',
          contentSeason: 1,
          contentEpisode: 2,
          subtitle: 'Extra',
          playlist: [
            PlaylistEntry(url: 'https://player.test/c1.mp4', title: 'Cut A'),
            PlaylistEntry(url: 'https://player.test/c2.mp4', title: 'Cut B'),
          ],
        ),
      );
      try {
        expect(playerControls(t).title, 'Cut A');
        expect(playerControls(t).subtitle, 'Extra');
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 a plain launch without identity shows the raw widget title on the TV dock',
    (t) async {
      final d = await _start(
        t,
        const VideoPlayerScreen(
          videoUrl: 'https://player.test/raw.mp4',
          title: 'Raw.Release.Name.mkv',
          subtitle: 'raw subtitle',
        ),
        tv: true,
      );
      try {
        expect(_tv(t).title, 'Raw.Release.Name.mkv');
        expect(_tv(t).titleIsClean, isFalse);
        expect(_tv(t).subtitle, 'raw subtitle');
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 Debrify TV shows the launch title raw, then the provider title raw',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: 'https://player.test/dtv-1.mp4',
          title: 'Debrify launch',
          contentTitle: 'Ignored catalog title',
          requestMagicNext: () async => {
            'url': 'https://player.test/dtv-2.mp4',
            'title': 'Torrent.Name.1080p',
          },
        ),
        tv: true,
      );
      try {
        expect(_tv(t).title, 'Debrify launch');
        expect(_tv(t).titleIsClean, isFalse);
        final dynamic next = _tv(t).onNext!;
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => next()) as Future<dynamic>,
        );
        await d.f.until(t, () => _tv(t).title == 'Torrent.Name.1080p');
        expect(_tv(t).titleIsClean, isFalse);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 IPTV on-demand channels title by numbered name and subtitle by group',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: 'https://branch.test/3.ts',
          title: 'Branch channel 3',
          iptvChannels: [
            _iptv(3, group: 'Films'),
            _iptv(4),
          ],
        ),
        tv: true,
      );
      try {
        expect(_tv(t).title, 'CH 3  Branch channel 3');
        expect(_tv(t).titleIsClean, isTrue);
        expect(_tv(t).subtitle, 'Films');
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P18 an IPTV channel without a group is subtitled "IPTV"', (
    t,
  ) async {
    final d = await _start(
      t,
      VideoPlayerScreen(
        videoUrl: 'https://branch.test/4.ts',
        title: 'Branch channel 4',
        iptvChannels: [_iptv(4)],
      ),
      tv: true,
    );
    try {
      expect(_tv(t).subtitle, 'IPTV');
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P18 a Stremio TV channel switch titles the dock by the dynamic title, clean',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: 'https://player.test/a.mp4',
          title: 'Stremio launch',
          stremioTvCurrentChannelId: 'a',
          stremioTvChannels: tvDirectory,
          stremioTvChannelSwitchProvider: (id) async => null,
        ),
        tv: true,
      );
      try {
        // The TV dock opens the same Stremio guide sheet.
        _tv(t).onShowGuide!();
        await d.f.until(
          t,
          () => find.byType(StremioTvGuideSheet).evaluate().isNotEmpty,
        );
        final guide = t.widget<StremioTvGuideSheet>(
          find.byType(StremioTvGuideSheet),
        );
        await d.stremioPick(guide, 'b');
        await d.f.until(t, () => _tv(t).title == 'Channel b');
        expect(_tv(t).titleIsClean, isTrue);
      } finally {
        await d.close();
      }
    },
  );
}
