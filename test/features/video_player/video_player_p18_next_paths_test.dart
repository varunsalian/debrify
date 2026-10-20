import 'dart:async';

import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player/widgets/transition_overlay.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

String _url(String name) =>
    'https://player.test/${Uri.encodeComponent(name)}.mp4';

PlaylistEntry _e(String name) => PlaylistEntry(url: _url(name), title: name);

/// Presses Next without awaiting it; the returned future completes with it.
Future<dynamic> _beginNext(TvEpisodeDriver d) {
  final dynamic next = playerControls(d.t).onNext!;
  return d.observe<dynamic>(() => next()) as Future<dynamic>;
}

Future<void> _next(TvEpisodeDriver d) async {
  await d.f.finish<dynamic>(d.t, _beginNext(d));
  await d.f.advance(d.t, const Duration(milliseconds: 200));
}

bool _videoShown() => find.byType(mkv.Video).evaluate().isNotEmpty;

Future<TvEpisodeDriver> _start(WidgetTester t, VideoPlayerScreen screen) async {
  final d = TvEpisodeDriver(t);
  await d.initialize();
  await d.mount(screen: screen);
  return d;
}

void main() {
  testWidgets(
    'P18 manual Next under continuous shuffle asks the show shuffle, not the pack order',
    (t) async {
      var reads = 0;
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('Mix.S01E01.mkv'),
          title: 'Mix.S01E01.mkv',
          contentType: 'series',
          contentSeason: 1,
          contentEpisode: 1,
          disableAutoResume: true,
          initialContinuousShuffle: true,
          playlist: [_e('Mix.S01E01.mkv'), _e('Mix.S01E02.mkv')],
          seriesSourceFetcher: SeriesSourceFetcher(
            season: 1,
            episode: 1,
            loadCustomEpisodeInventory: () async {
              reads++;
              return [
                for (final n in [1, 2])
                  {'season': 1, 'number': n, 'airdate': '2020-01-0$n'},
              ];
            },
            searchEpisodes: (s, e) async => [],
            searchPacks: (s, e) async => [],
          ),
          resolveSourceToPlaylist: (s, {canContinue}) async => [],
        ),
      );
      try {
        final before = d.opens.length;
        await _next(d);
        await d.f.until(t, () => d.opens.length > before);
        expect(reads, 1, reason: 'continuous shuffle owns manual Next');
        expect(d.opens.last.uri, _url('Mix.S01E02.mkv'));
        expect(d.openAutoplay.last, isTrue);
        expect(_videoShown(), isTrue);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 ordered manual Next autoplays the next item and restores the video',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('a'),
          title: 'Files',
          viewMode: PlaylistViewMode.raw,
          disableAutoResume: true,
          startIndex: 0,
          playlist: [_e('a'), _e('b')],
        ),
      );
      try {
        await _next(d);
        expect(d.opens.last.uri, _url('b'));
        expect(d.openAutoplay.last, isTrue);
        expect(_videoShown(), isTrue);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 a failed Next load drops the transition curtain and shows the video again',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('a'),
          title: 'Files',
          viewMode: PlaylistViewMode.raw,
          disableAutoResume: true,
          startIndex: 0,
          playlist: [
            _e('a'),
            const PlaylistEntry(
              url: '',
              title: 'tb',
              torboxTorrentId: 41,
              torboxFileId: 7,
            ),
          ],
        ),
      );
      try {
        final before = d.opens.length;
        await _next(d);
        expect(
          find.text('Failed to prepare video: Missing Torbox API key'),
          findsOneWidget,
        );
        expect(d.opens.length, before);
        expect(_videoShown(), isTrue);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 Debrify TV Next hides the video behind static until the provider answers',
    (t) async {
      final answer = Completer<Map<String, String>?>();
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: 'https://player.test/dtv-1.mp4',
          title: 'Debrify launch',
          requestMagicNext: () => answer.future,
        ),
      );
      try {
        final pressed = _beginNext(d);
        await d.f.advance(t, const Duration(milliseconds: 200));
        expect(_videoShown(), isFalse, reason: 'transition curtain is up');
        expect(find.byType(TransitionOverlay), findsOneWidget);
        answer.complete({
          'url': 'https://player.test/dtv-2.mp4',
          'title': 'Static title',
        });
        await d.f.finish<dynamic>(t, pressed);
        final overlay = find.byType(TransitionOverlay);
        expect(overlay, findsOneWidget);
        final widget = t.widget<TransitionOverlay>(overlay);
        expect(widget.tvStaticMessage, '📺 SIGNAL ACQUIRED');
        expect(widget.tvStaticSubtext, '▶ STATIC TITLE');
        await d.f.advance(t, const Duration(milliseconds: 200));
        expect(_videoShown(), isTrue);
      } finally {
        if (!answer.isCompleted) answer.complete(null);
        await d.close();
      }
    },
  );

  for (final (label, result) in <(String, Map<String, String>?)>[
    ('no answer', null),
    ('an answer without a URL', <String, String>{'title': 'Untitled'}),
  ]) {
    testWidgets(
      'P18 Debrify TV Next with $label opens nothing and restores the video',
      (t) async {
        final d = await _start(
          t,
          VideoPlayerScreen(
            videoUrl: 'https://player.test/dtv-1.mp4',
            title: 'Debrify launch',
            requestMagicNext: () async => result,
          ),
        );
        try {
          final before = d.opens.length;
          await _next(d);
          expect(d.opens.length, before);
          expect(_videoShown(), isTrue);
          expect(playerControls(t).title, 'Debrify launch');
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P18 Debrify TV Next without a title keeps the current title and is not PikPak',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: 'https://player.test/dtv-1.mp4',
          title: 'Debrify launch',
          requestMagicNext: () async => {
            'url': 'https://player.test/dtv-2.mp4',
          },
        ),
      );
      try {
        await _next(d);
        expect(d.opens.last.uri, 'https://player.test/dtv-2.mp4');
        expect(playerControls(t).title, 'Debrify launch');
        expect(
          d.logs.any(
            (l) => l.contains('Detected PikPak video from Debrify TV'),
          ),
          isFalse,
        );
        expect(
          d.logs.any(
            (l) =>
                l.contains('MagicTV next success') &&
                l.contains('(provider: , pikpakFileId: )'),
          ),
          isTrue,
        );
      } finally {
        await d.close();
      }
    },
  );

  for (final (label, result) in [
    ('provider', <String, String>{'provider': 'PikPak'}),
    ('file id', <String, String>{'pikpakFileId': 'pk-1'}),
  ]) {
    testWidgets(
      'P18 Debrify TV Next with a PikPak $label uses the PikPak retry open',
      (t) async {
        final d = await _start(
          t,
          VideoPlayerScreen(
            videoUrl: 'https://player.test/dtv-1.mp4',
            title: 'Debrify launch',
            requestMagicNext: () async => {
              'url': 'https://player.test/dtv-pk.mp4',
              'title': 'Cold one',
              ...result,
            },
          ),
        );
        try {
          await _next(d);
          await d.f.until(
            t,
            () => d.logs.any(
              (l) => l.contains('PikPak: Video metadata loaded successfully'),
            ),
          );
          expect(
            d.logs.any(
              (l) => l.contains('Detected PikPak video from Debrify TV'),
            ),
            isTrue,
          );
          expect(d.opens.last.uri, 'https://player.test/dtv-pk.mp4');
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P18 Debrify TV Next with a random start seeks inside the new item',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: 'https://player.test/dtv-1.mp4',
          title: 'Debrify launch',
          startFromRandom: true,
          requestMagicNext: () async => {
            'url': 'https://player.test/dtv-2.mp4',
            'title': 'Random',
          },
        ),
      );
      try {
        final before = d.seeks.length;
        await _next(d);
        await d.f.until(t, () => d.seeks.length > before);
        final seek = d.seeks.last;
        expect(seek, greaterThan(Duration.zero));
        expect(seek, lessThan(const Duration(minutes: 20)));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 manual Previous autoplays the previous item and restores the video',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('b'),
          title: 'Files',
          viewMode: PlaylistViewMode.raw,
          disableAutoResume: true,
          startIndex: 1,
          playlist: [_e('a'), _e('b')],
        ),
      );
      try {
        final dynamic previous = playerControls(t).onPrevious!;
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => previous()) as Future<dynamic>,
        );
        await d.f.advance(t, const Duration(milliseconds: 200));
        expect(d.opens.last.uri, _url('a'));
        expect(d.openAutoplay.last, isTrue);
        expect(_videoShown(), isTrue);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 Next to an entry with no URL and no provider explains it and keeps playing',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('a'),
          title: 'Files',
          viewMode: PlaylistViewMode.raw,
          disableAutoResume: true,
          startIndex: 0,
          playlist: [
            _e('a'),
            const PlaylistEntry(url: '', title: 'blank'),
          ],
        ),
      );
      try {
        final before = d.opens.length;
        await _next(d);
        // The resolver's own failure notice is queued ahead of this one.
        const none = 'No playable URL found for this entry';
        for (var i = 0; i < 20; i++) {
          if (find.text(none).evaluate().isNotEmpty) break;
          await d.f.advance(t, const Duration(seconds: 1));
        }
        expect(find.text(none), findsOneWidget);
        expect(d.opens.length, before);
        expect(_videoShown(), isTrue);
      } finally {
        await d.close();
      }
    },
  );
}
