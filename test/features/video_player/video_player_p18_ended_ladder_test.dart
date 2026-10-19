import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'support/trakt_transport.dart';
import 'support/tv_episode_driver.dart';

const _id = 'simkl:86420019';

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

/// Simkl episode list for [_id]; [episodes] decides whether a next exists.
FutureOr<http.Response> Function(http.Request) _simkl(
  List<int> episodes,
  List<Uri> lookups,
) => (r) {
  if (r.url.path.contains('/tv/episodes/86420019')) {
    lookups.add(r.url);
    return http.Response(
      jsonEncode([
        for (final n in episodes) {'season': 1, 'episode': n, 'title': 'E$n'},
      ]),
      200,
    );
  }
  return http.Response('{}', 404);
};

Future<TvEpisodeDriver> _driver(WidgetTester t) async {
  final d = TvEpisodeDriver(t);
  await d.initialize();
  TraktTestTransport.instance.attach(d.f);
  return d;
}

Future<void> _done(TvEpisodeDriver d) async {
  TraktTestTransport.instance.recorder = null;
  await d.close();
}

Future<void> _ended(TvEpisodeDriver d) async {
  d.player.emit('completed', true);
  await d.f.advance(d.t, const Duration(milliseconds: 300));
  await d.f.actions.settle(d.t);
}

void main() {
  testWidgets(
    'P18 EOF inside a catalog series pack loads the next pack episode and stays',
    (t) async {
      final d = await _driver(t);
      final lookups = <Uri>[];
      var popped = false;
      try {
        d.f.network.handler = _simkl([1, 2, 3], lookups);
        final route = await _mountRoute(
          d,
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/l1.mp4',
            title: 'Ladder pack',
            contentImdbId: _id,
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            playlist: [
              PlaylistEntry(
                url: 'https://player.test/l1.mp4',
                title: 'Ladder.S01E01.mkv',
              ),
              PlaylistEntry(
                url: 'https://player.test/l2.mp4',
                title: 'Ladder.S01E02.mkv',
              ),
            ],
          ),
        );
        unawaited(route.then((_) => popped = true));
        final atEnd = lookups.length;
        await _ended(d);
        await d.f.until(
          t,
          () => d.opens.last.uri == 'https://player.test/l2.mp4',
        );
        await d.f.advance(t, const Duration(seconds: 2));
        expect(popped, isFalse);
        expect(
          lookups.length,
          atEnd,
          reason: 'no hand-off lookup inside the pack',
        );
      } finally {
        await _done(d);
      }
    },
  );

  testWidgets(
    'P18 EOF on the last pack episode hands the next catalog episode to Quick Play',
    (t) async {
      final d = await _driver(t);
      final lookups = <Uri>[];
      try {
        d.f.network.handler = _simkl([1, 2], lookups);
        final route = await _mountRoute(
          d,
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/l1.mp4',
            title: 'Ladder pack',
            contentImdbId: _id,
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            playlist: [
              PlaylistEntry(
                url: 'https://player.test/l1.mp4',
                title: 'Ladder.S01E01.mkv',
              ),
            ],
          ),
        );
        final atEnd = lookups.length;
        await _ended(d);
        final result = await d.f.finish(t, route);
        expect((result as Map)['episode'], 2);
        expect(result['season'], 1);
        expect(lookups.length - atEnd, 1);
      } finally {
        await _done(d);
      }
    },
  );

  testWidgets(
    'P18 EOF on the series finale looks the next episode up once and stays',
    (t) async {
      final d = await _driver(t);
      final lookups = <Uri>[];
      var popped = false;
      try {
        d.f.network.handler = _simkl([1], lookups);
        final route = await _mountRoute(
          d,
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/finale.mp4',
            title: 'Finale',
            contentImdbId: _id,
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
          ),
        );
        unawaited(route.then((_) => popped = true));
        final atEnd = lookups.length;
        await _ended(d);
        await d.f.advance(t, const Duration(seconds: 2));
        expect(popped, isFalse);
        expect(lookups.length - atEnd, 1);
      } finally {
        await _done(d);
      }
    },
  );

  testWidgets(
    'P18 Debrify TV EOF with series identity advances by provider and never hands off',
    (t) async {
      final d = await _driver(t);
      final lookups = <Uri>[];
      var popped = false;
      try {
        d.f.network.handler = _simkl([1, 2], lookups);
        final route = await _mountRoute(
          d,
          VideoPlayerScreen(
            videoUrl: 'https://player.test/dtv.mp4',
            title: 'Debrify',
            contentImdbId: _id,
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            requestMagicNext: () async => {
              'url': 'https://player.test/dtv-next.mp4',
              'title': 'Next up',
            },
          ),
        );
        unawaited(route.then((_) => popped = true));
        final atEnd = lookups.length;
        await _ended(d);
        await d.f.until(
          t,
          () => d.opens.last.uri == 'https://player.test/dtv-next.mp4',
        );
        await d.f.advance(t, const Duration(seconds: 2));
        expect(popped, isFalse);
        expect(lookups.length, atEnd);
      } finally {
        await _done(d);
      }
    },
  );
}
