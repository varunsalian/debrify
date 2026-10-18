import 'dart:async';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/skip_segment_driver.dart';
import 'support/tv_episode_driver.dart';

void main() {
  for (final initial in [null, '', 'a']) {
    testWidgets('P17 Stremio initial id $initial and guide gating', (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            stremioTvCurrentChannelId: initial,
            stremioTvChannels: tvDirectory,
            stremioTvChannelSwitchProvider: (id) async => null,
          ),
        );
        final g = await d.stremioGuide();
        expect(g.currentChannelId, initial);
        g.onClose();
        await d.f.advance(t);
        expect(find.byType(StremioTvGuideSheet), findsNothing);
      } finally {
        await d.close();
      }
    });
  }
  testWidgets(
    'P17 Stremio replaces every outer map and shallow shares nested guide data',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final nested = {'title': 'original'};
      final other = {
        'id': 'a',
        'name': 'Alpha',
        'nowPlaying': nested,
        'tags': <String>['shared'],
      };
      final matching = {
        'id': 'b',
        'name': 'Beta',
        'nowPlaying': {'title': 'old'},
      };
      final now = {'title': 'New', 'nested': nested};
      final next = {'title': 'Following'};
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            stremioTvCurrentChannelId: 'a',
            stremioTvChannels: [other, matching],
            stremioTvChannelSwitchProvider: (id) async => null,
          ),
        );
        final g = await d.stremioGuide();
        final before = g.channels;
        await d.stremioPick(
          g,
          'b',
          nowPlaying: now,
          nextUp: next,
          imdbId: 'tt2222222',
          season: 2,
          episode: 4,
        );
        final updated = await d.stremioGuide();
        expect(updated.currentChannelId, 'b');
        expect(identical(updated.channels, before), isFalse);
        for (var i = 0; i < 2; i++) {
          expect(identical(updated.channels[i], before[i]), isFalse);
        }
        expect(updated.channels.first, other);
        expect(identical(updated.channels.first['nowPlaying'], nested), isTrue);
        expect(
          identical(updated.channels.first['tags'], other['tags']),
          isTrue,
        );
        expect(updated.channels.last['nowPlaying'], now);
        expect(identical(updated.channels.last['nowPlaying'], now), isFalse);
        expect(
          identical(
            (updated.channels.last['nowPlaying'] as Map)['nested'],
            nested,
          ),
          isTrue,
        );
        expect(updated.channels.last['nextUp'], next);
        expect(identical(updated.channels.last['nextUp'], next), isFalse);
        expect(() => updated.channels.add({'id': 'c'}), throwsUnsupportedError);
        expect(matching['nowPlaying'], {'title': 'old'});
        expect(d.opens.last.uri, 'https://player.test/b.mp4');
        expect(d.openAutoplay, everyElement(isTrue));
        expect(d.player.state.track.subtitle.id, 'no');
        expect(
          d.player.calls.map((c) => c.$1),
          containsAllInOrder(['pause', 'open', 'subtitle']),
        );
      } finally {
        await d.close();
      }
    },
  );
  for (final raw in ['non-list', 'mixed', 'none']) {
    testWidgets(
      'P17 Stremio next parses $raw sources and coerces numeric fields',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final skip = SkipSegmentDriver(t, d.f);
        await skip.configure();
        final source = episodeSource('B.S02E04');
        var requested = '';
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'A',
              stremioTvCurrentChannelId: 'a',
              stremioTvChannels: tvDirectory,
              stremioTvChannelSwitchProvider: (id) async => null,
              stremioTvNextProvider: (id) async {
                requested = id;
                return {
                  'url': 'https://player.test/b.mp4',
                  'title': 'Beta',
                  'channelId': 'b',
                  'contentImdbId': 'tt2222222',
                  'contentType': 'series',
                  'contentSeason': 2.9,
                  'contentEpisode': 4.9,
                  'startAtPercent': 0.25,
                  'nowPlaying': {'title': 'Now'},
                  'nextUp': {'title': 'Next'},
                  'stremioSources': raw == 'mixed'
                      ? [false, source.toJson(), null]
                      : raw == 'non-list'
                      ? 42
                      : null,
                  'stremioCurrentSourceIndex': 0.0,
                  'sourceResolver': (dynamic candidate) async =>
                      'https://player.test/resolved.mp4',
                };
              },
            ),
          );
          d.player.onOpen = () {};
          final dynamic next = playerControls(t).onNext!;
          await d.f.finish<dynamic>(t, d.observe<dynamic>(() => next()));
          await d.f.advance(t);
          expect(requested, 'a');
          expect(d.opens.last.uri, 'https://player.test/b.mp4');
          expect(d.openAutoplay, everyElement(isTrue));
          final before = d.seeks.length;
          await skip.duration(const Duration(seconds: 200));
          await d.f.until(t, () => skip.requests.isNotEmpty);
          skip.expectQuery(
            id: 'tt2222222',
            season: 2,
            episode: 4,
            seconds: 200,
          );
          expect(d.seeks.skip(before), [const Duration(seconds: 50)]);
          final guide = await d.stremioGuide();
          expect(guide.currentChannelId, 'b');
          expect(guide.channels.last['nowPlaying'], {'title': 'Now'});
          guide.onClose();
          await d.f.advance(t);
          if (raw == 'mixed') {
            final sheet = await d.sourceSheet();
            expect(sheet.sources, hasLength(1));
            expect(sheet.sources.single.name, source.name);
            expect(sheet.currentSourceIndex, 0);
            expect(
              await d.f.finish(t, sheet.resolveSource(sheet.sources.single)),
              'https://player.test/resolved.mp4',
            );
          } else {
            expect(playerControls(t).onShowStremioSources, isNull);
          }
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final failure in ['throw', 'null', 'empty']) {
    testWidgets(
      'P17 Stremio next $failure dedupes only the provider window and resumes',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final held = Completer<Map<String, dynamic>?>();
        var count = 0;
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'A',
              stremioTvCurrentChannelId: 'a',
              stremioTvNextProvider: (id) async {
                count++;
                final value = await held.future;
                if (failure == 'throw') {
                  throw StateError('next rejected');
                }
                return value;
              },
            ),
          );
          final dynamic next = playerControls(t).onNext!;
          final first = d.observe<dynamic>(() => next()) as Future<dynamic>;
          await d.f.until(t, () => count == 1);
          await d.f.finish<dynamic>(t, d.observe<dynamic>(() => next()));
          expect(count, 1);
          expect(find.text('Loading next...'), findsOneWidget);
          held.complete(failure == 'null' ? null : {'url': ''});
          await d.f.finish(t, first);
          await d.f.advance(t);
          expect(d.player.calls.where((c) => c.$1 == 'play'), hasLength(1));
          expect(d.player.state.playing, isTrue);
          expect(d.opens, hasLength(1));
          expect(find.text('Loading next...'), findsNothing);
        } finally {
          if (!held.isCompleted) {
            held.complete(null);
          }
          await d.close();
        }
      },
    );
  }
  for (final alreadyEmitted in [false, true]) {
    testWidgets(
      'P17 Stremio start percent subscribes after open and seeks once emitted=$alreadyEmitted',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'A',
              stremioTvChannels: tvDirectory,
              stremioTvChannelSwitchProvider: (id) async => null,
            ),
          );
          final g = await d.stremioGuide();
          d.player.onOpen = alreadyEmitted
              ? () => d.player.emit('duration', const Duration(seconds: 100))
              : () {};
          final before = d.seeks.length;
          await d.stremioPick(g, 'b', startAtPercent: 0.25);
          expect(d.seeks.length, before);
          d.player.emit('duration', Duration.zero);
          await d.f.advance(t);
          expect(d.seeks.length, before);
          d.player.emit('duration', const Duration(seconds: 200));
          await d.f.advance(t);
          expect(d.seeks.skip(before), [const Duration(seconds: 50)]);
          d.player.emit('duration', const Duration(seconds: 400));
          await d.f.advance(t);
          expect(d.seeks.length, before + 1);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P17 Stremio older start-percent listener seeks the newly picked channel',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            stremioTvChannels: tvDirectory,
            stremioTvChannelSwitchProvider: (id) async => null,
          ),
        );
        final g = await d.stremioGuide();
        d.player.onOpen = () {};
        await d.stremioPick(g, 'b', startAtPercent: 0.4);
        await d.stremioPick(g, 'c');
        final before = d.seeks.length;
        d.player.emit('duration', const Duration(seconds: 300));
        await d.f.advance(t);
        expect(d.opens.last.uri, 'https://player.test/c.mp4');
        expect(d.seeks.skip(before), [const Duration(seconds: 120)]);
      } finally {
        await d.close();
      }
    },
  );
  for (final failed in [false, true]) {
    testWidgets(
      'P17 Stremio EOF next resumeCurrentOnFailure false failed=$failed',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        var calls = 0;
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'A',
              stremioTvCurrentChannelId: 'a',
              stremioTvNextProvider: (id) async {
                calls++;
                return failed
                    ? {'url': ''}
                    : {'url': 'https://player.test/next.mp4'};
              },
            ),
          );
          d.player.state = d.player.state.copyWith(
            playing: false,
            completed: true,
          );
          d.player.emit('playing', false);
          d.player.emit('completed', true);
          await d.f.until(t, () => calls == 1);
          await d.f.actions.settle(t);
          expect(d.player.calls.where((c) => c.$1 == 'play'), isEmpty);
          expect(d.opens.length, failed ? 1 : 2);
          if (failed) {
            expect(
              d.logs,
              contains(
                'Player: Stremio TV auto-next unavailable; leaving playback ended.',
              ),
            );
          } else {
            expect(d.opens.last.uri, 'https://player.test/next.mp4');
          }
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P17 guide source index defaults to zero and omitted source fields retain the live resolver',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final first = episodeSource('First.S01E02');
      final second = episodeSource('Second.S01E02');
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            stremioTvChannels: tvDirectory,
            stremioTvChannelSwitchProvider: (id) async => null,
          ),
        );
        final g = await d.stremioGuide();
        await d.stremioPick(
          g,
          'b',
          sources: [first, second],
          resolver: (source) async => 'https://player.test/remembered.mp4',
        );
        var sheet = await d.sourceSheet();
        expect(sheet.currentSourceIndex, 0);
        sheet.onClose();
        await d.f.advance(t);
        await d.stremioPick(g, 'c', sources: [first, second], sourceIndex: 1);
        await d.stremioPick(g, 'd');
        sheet = await d.sourceSheet();
        expect(sheet.currentSourceIndex, 1);
        expect(sheet.sources, [first, second]);
        expect(
          await d.f.finish(t, sheet.resolveSource(second)),
          'https://player.test/remembered.mp4',
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P17 unawaited start-percent duration closed before positive sample reports StateError to its zone',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            stremioTvChannels: tvDirectory,
            stremioTvChannelSwitchProvider: (id) async => null,
          ),
        );
        final g = await d.stremioGuide();
        d.player.onOpen = () {};
        await d.stremioPick(g, 'b', startAtPercent: 0.2);
      } finally {
        await d.close();
      }
      expect(d.errors, hasLength(1));
      expect(d.errors.single, isA<StateError>());
    },
  );
  testWidgets('P17 older Stremio next payload overwrites a newer guide pick', (
    t,
  ) async {
    final d = TvEpisodeDriver(t);
    await d.initialize();
    final held = Completer<Map<String, dynamic>?>();
    var requested = false;
    Future<dynamic>? old;
    try {
      await d.mount(
        screen: VideoPlayerScreen(
          videoUrl: 'https://player.test/a.mp4',
          title: 'A',
          stremioTvCurrentChannelId: 'a',
          stremioTvChannels: tvDirectory,
          stremioTvChannelSwitchProvider: (id) async => null,
          stremioTvNextProvider: (id) {
            requested = true;
            return held.future;
          },
        ),
      );
      final guide = await d.stremioGuide();
      guide.onClose();
      await d.f.advance(t);
      final dynamic next = playerControls(t).onNext!;
      old = d.observe<dynamic>(() => next()) as Future<dynamic>;
      await d.f.until(t, () => requested);
      await d.stremioPick(guide, 'b');
      held.complete({
        'url': 'https://player.test/old.mp4',
        'channelId': 'old',
        'title': 'Old next',
      });
      await d.f.finish(t, old);
      old = null;
      expect(d.opens.map((v) => v.uri), [
        'https://player.test/a.mp4',
        'https://player.test/b.mp4',
        'https://player.test/old.mp4',
      ]);
      expect((await d.stremioGuide()).currentChannelId, 'old');
      expect(d.errors, isEmpty);
    } finally {
      if (!held.isCompleted) {
        held.complete(null);
      }
      if (old != null) {
        await d.f.finish(t, old);
      }
      await d.close();
    }
  });
  testWidgets(
    'P17 older Stremio guide pause opens after the newer pick but retains its newer identity',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final held = Completer<void>();
      var entered = false;
      Future<dynamic>? old;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            stremioTvCurrentChannelId: 'a',
            stremioTvChannels: tvDirectory,
            stremioTvChannelSwitchProvider: (id) async => null,
          ),
        );
        final guide = await d.stremioGuide();
        d.player.beforeOperation = (name, value) async {
          if (name == 'pause' && !entered) {
            entered = true;
            await held.future;
          }
        };
        d.player.heldOperation = (name, value) =>
            name == 'pause' && !held.isCompleted;
        final dynamic pick = guide.onChannelSwitched;
        old =
            d.observe<dynamic>(
                  () => pick('b', 'https://player.test/b.mp4', 'B'),
                )
                as Future<dynamic>;
        await d.f.until(t, () => entered);
        await d.stremioPick(guide, 'c');
        held.complete();
        await d.f.finish(t, old);
        old = null;
        expect(d.opens.map((v) => v.uri), [
          'https://player.test/a.mp4',
          'https://player.test/c.mp4',
          'https://player.test/b.mp4',
        ]);
        expect((await d.stremioGuide()).currentChannelId, 'c');
        expect(d.errors, isEmpty);
      } finally {
        if (!held.isCompleted) {
          held.complete();
        }
        if (old != null) {
          await d.f.finish(t, old);
        }
        await d.close();
      }
    },
  );

  testWidgets(
    'P17 Stremio next releases dedupe before its first open finishes',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final held = Completer<void>();
      var openEntered = false;
      final requested = <String>[];
      Future<dynamic>? first;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            stremioTvCurrentChannelId: 'a',
            stremioTvChannels: tvDirectory,
            stremioTvChannelSwitchProvider: (id) async => null,
            stremioTvNextProvider: (id) async {
              requested.add(id);
              return {
                'url': 'https://player.test/slot${requested.length}.mp4',
                'channelId': 's${requested.length}',
              };
            },
          ),
        );
        d.player.beforeOperation = (name, value) async {
          if (name == 'open' && !openEntered) {
            openEntered = true;
            await held.future;
          }
        };
        d.player.heldOperation = (name, value) =>
            name == 'open' && !held.isCompleted;
        final dynamic next = playerControls(t).onNext!;
        first = d.observe<dynamic>(() => next()) as Future<dynamic>;
        await d.f.until(t, () => openEntered);
        expect(requested, ['a']);
        expect(find.text('Loading next...'), findsNothing);
        await d.f.finish<dynamic>(t, d.observe<dynamic>(() => next()));
        expect(requested, ['a', 's1']);
        expect(
          d.player.state.playlist.medias.single.uri,
          'https://player.test/slot2.mp4',
        );
        held.complete();
        await d.f.finish(t, first);
        first = null;
        expect(
          d.player.state.playlist.medias.single.uri,
          'https://player.test/slot1.mp4',
        );
        expect((await d.stremioGuide()).currentChannelId, 's2');
        expect(d.errors, isEmpty);
      } finally {
        if (!held.isCompleted) {
          held.complete();
        }
        if (first != null) {
          await d.f.finish(t, first);
        }
        await d.close();
      }
    },
  );

  for (final missing in ['null directory', 'empty directory', 'provider']) {
    testWidgets(
      'P17 captured Stremio guide opener refuses $missing after widget update',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'A',
              stremioTvChannels: tvDirectory,
              stremioTvChannelSwitchProvider: (id) async => null,
            ),
          );
          final open = playerControls(t).onShowGuide!;
          await d.observe(
            () => t.pumpWidget(
              MaterialApp(
                navigatorKey: d.f.navigator,
                theme: ThemeData.dark(),
                home: VideoPlayerScreen(
                  videoUrl: 'https://player.test/a.mp4',
                  title: 'A',
                  stremioTvChannels: missing == 'null directory'
                      ? null
                      : missing == 'empty directory'
                      ? const []
                      : tvDirectory,
                  stremioTvChannelSwitchProvider: missing == 'provider'
                      ? null
                      : (id) async => null,
                ),
              ),
            ),
          );
          expect(d.f.players, hasLength(1));
          expect(playerControls(t).onShowGuide, isNull);
          open();
          await d.f.advance(t);
          expect(find.byType(StremioTvGuideSheet), findsNothing);
          expect(d.opens, hasLength(1));
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
