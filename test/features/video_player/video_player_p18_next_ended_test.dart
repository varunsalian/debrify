import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'support/player_actions.dart';
import 'support/trakt_transport.dart';
import 'support/tv_episode_driver.dart';

PlaylistEntry _e(String name, {int? size}) => PlaylistEntry(
  url: 'https://player.test/${Uri.encodeComponent(name)}.mp4',
  title: name,
  sizeBytes: size,
);

String _url(String name) =>
    'https://player.test/${Uri.encodeComponent(name)}.mp4';

Future<void> _ended(TvEpisodeDriver d) async {
  d.player.emit('completed', true);
  await d.f.advance(d.t, const Duration(milliseconds: 300));
  await d.f.actions.settle(d.t);
}

Future<void> _pressNext(TvEpisodeDriver d) async {
  final dynamic callback = playerControls(d.t).onNext!;
  await d.f.finish<dynamic>(
    d.t,
    d.observe<dynamic>(() => callback()) as Future<dynamic>,
  );
  await d.f.advance(d.t, const Duration(milliseconds: 200));
}

/// Mounts [screen] as a pushed route so its pop result is observable.
Future<Future<Object?>> _mountRoute(
  TvEpisodeDriver d,
  VideoPlayerScreen screen,
) async {
  final t = d.t;
  final f = d.f;
  t.view.physicalSize = const Size(1280, 800);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    MaterialApp(
      navigatorKey: f.navigator,
      theme: ThemeData.dark(),
      home: const Text('host'),
    ),
  );
  late Future<Object?> popped;
  d.observe(() {
    popped = f.navigator.currentState!.push<Object?>(
      MaterialPageRoute(builder: (_) => screen),
    );
  });
  await f.until(t, () => f.controllers.isNotEmpty);
  f.player.deliverReady();
  await f.until(t, () => f.player.calls.any((c) => c.$1 == 'open'));
  for (var i = 0; i < 20; i++) {
    await f.advance(t, const Duration(milliseconds: 100));
  }
  expect(find.byType(mkv.Video), findsOneWidget);
  return popped;
}

http.Response _simklEpisodes(http.Request r) =>
    r.url.path.contains('/tv/episodes/86420018')
    ? http.Response(
        jsonEncode([
          {'season': 1, 'episode': 1, 'title': 'First'},
          {'season': 1, 'episode': 2, 'title': 'Second'},
        ]),
        200,
      )
    : http.Response('{}', 404);

void main() {
  testWidgets(
    'P18 EOF on a collection advances to the next main-group item and autoplays',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _url('Movie A 2005'),
            title: 'Collection',
            contentType: 'movie',
            playlist: [_e('Movie A 2005'), _e('Movie B 2010')],
          ),
        );
        final before = d.opens.length;
        await _ended(d);
        await d.f.until(t, () => d.opens.length > before);
        expect(d.opens.last.uri, _url('Movie B 2010'));
        expect(d.openAutoplay.last, isTrue);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 EOF on the last non-series item opens nothing and stays on the route',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _url('Movie A 2005'),
            title: 'Collection',
            contentType: 'movie',
            disableAutoResume: true,
            startIndex: 1,
            playlist: [_e('Movie A 2005'), _e('Movie B 2010')],
          ),
        );
        final before = d.opens.length;
        await _ended(d);
        await d.f.advance(t, const Duration(seconds: 2));
        expect(d.opens.length, before);
        expect(find.byType(mkv.Video), findsOneWidget);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 continuous shuffle owns EOF: the next open is the only other playlist item',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _url('a'),
            title: 'Files',
            contentType: 'movie',
            disableAutoResume: true,
            startIndex: 0,
            initialContinuousShuffle: true,
            playlist: [_e('a'), _e('b')],
          ),
        );
        final before = d.opens.length;
        await _ended(d);
        await d.f.until(t, () => d.opens.length > before);
        expect(d.opens.last.uri, _url('b'));
        expect(d.openAutoplay.last, isTrue);
        await _ended(d);
        await d.f.until(t, () => d.opens.length > before + 1);
        expect(
          d.opens.last.uri,
          _url('a'),
          reason: 'the shuffle bag never repeats the current item',
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 Debrify TV magic Next opens the provider URL, adopts its title and disables embedded subtitles',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      var requests = 0;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/magic-1.mp4',
            title: 'Magic one',
            requestMagicNext: () async {
              requests++;
              return {
                'url': 'https://player.test/magic-2.mp4',
                'title': 'Magic two',
                'provider': 'realdebrid',
              };
            },
          ),
        );
        await _pressNext(d);
        await d.f.until(t, () => d.opens.length >= 2);
        expect(requests, 1);
        expect(d.opens.last.uri, 'https://player.test/magic-2.mp4');
        expect(d.openAutoplay.last, isTrue);
        await d.f.advance(t, const Duration(milliseconds: 500));
        expect(playerControls(t).title, 'Magic two');
        expect(
          d.player.calls.where(
            (c) => c.$1 == 'subtitle' && c.$2 == mk.SubtitleTrack.no(),
          ),
          isNotEmpty,
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 Debrify TV magic Next with startAtPercent seeks into the new item',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/magic-1.mp4',
            title: 'Magic one',
            startAtPercent: 0.5,
            requestMagicNext: () async => {
              'url': 'https://player.test/magic-2.mp4',
              'title': 'Magic two',
            },
          ),
        );
        final seeksBefore = d.seeks.length;
        await _pressNext(d);
        await d.f.until(t, () => d.seeks.length > seeksBefore);
        // startAtPercent is a fraction; publishFrame reports 20 minutes.
        expect(d.seeks.last, const Duration(minutes: 10));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 Debrify TV magic Next without a URL leaves playback on the current item',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/magic-1.mp4',
            title: 'Magic one',
            requestMagicNext: () async => {'url': '', 'title': 'Nothing'},
          ),
        );
        final before = d.opens.length;
        await _pressNext(d);
        await d.f.advance(t, const Duration(seconds: 1));
        expect(d.opens.length, before);
        expect(playerControls(t).title, isNot('Nothing'));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 Debrify TV EOF without a playlist advances through the magic provider',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      var requests = 0;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/magic-1.mp4',
            title: 'Magic one',
            requestMagicNext: () async {
              requests++;
              return {'url': 'https://player.test/magic-eof.mp4', 'title': 'E'};
            },
          ),
        );
        await _ended(d);
        await d.f.until(t, () => d.opens.length >= 2);
        expect(requests, 1);
        expect(d.opens.last.uri, 'https://player.test/magic-eof.mp4');
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 catalog series EOF pops the route once with the next episode for Quick Play',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      TraktTestTransport.instance.attach(d.f);
      try {
        d.f.network.handler = _simklEpisodes;
        final popped = await _mountRoute(
          d,
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/series-next.mp4',
            title: 'Series file',
            contentTitle: 'Clean Series',
            contentImdbId: 'simkl:86420018',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
          ),
        );
        d.player.emit('completed', true);
        final result = await d.f.finish(t, popped);
        expect(result, {
          'quickPlayNext': true,
          'imdbId': 'simkl:86420018',
          'season': 1,
          'episode': 2,
          'title': 'Clean Series',
          'contentType': 'series',
        });
        expect(find.text('host'), findsOneWidget);
      } finally {
        TraktTestTransport.instance.recorder = null;
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 manual Next racing EOF hands the next episode back exactly once',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      TraktTestTransport.instance.attach(d.f);
      final lookup = Completer<http.Response>();
      var lookups = 0;
      try {
        d.f.network.handler = (r) {
          if (r.url.path.contains('/tv/episodes/86420018')) {
            lookups++;
            return lookup.future;
          }
          return http.Response('{}', 404);
        };
        var pops = 0;
        final popped = await _mountRoute(
          d,
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/series-race.mp4',
            title: 'Series file',
            contentImdbId: 'simkl:86420018',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
          ),
        );
        unawaited(popped.then((_) => pops++));
        d.player.emit('completed', true);
        await d.f.advance(t, const Duration(milliseconds: 100));
        final dynamic next = playerControls(t).onNext!;
        final manual = d.observe<dynamic>(() => next()) as Future<dynamic>;
        await d.f.until(t, () => lookups >= 1);
        lookup.complete(
          _simklEpisodes(
            http.Request(
              'GET',
              Uri.parse('https://api.simkl.com/tv/episodes/86420018'),
            ),
          ),
        );
        await d.f.finish(t, popped);
        await d.f.finish<dynamic>(t, manual);
        await d.f.advance(t, const Duration(seconds: 1));
        expect(pops, 1);
        expect(find.text('host'), findsOneWidget);
      } finally {
        TraktTestTransport.instance.recorder = null;
        await d.close();
      }
    },
  );
}
