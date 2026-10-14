import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'support/player_actions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/identify_title_driver.dart';
import 'support/trakt_transport.dart';
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

void main() {
  TraktTestTransport.install();
  for (final entry in [
    (
      title: 'Show.Name.S02E03.1080p.mkv',
      query: 'Show Name',
      s: 2,
      e: 3,
      playlist: false,
    ),
    (
      title: 'Movie.Name.2024.1080p.mkv',
      query: 'Movie Name',
      s: 5,
      e: 6,
      playlist: false,
    ),
    (title: 'Raw__file...MPEG', query: 'Raw file', s: 5, e: 6, playlist: false),
    (
      title: 'Raw   file\t name .mkv',
      query: 'Raw file name',
      s: 5,
      e: 6,
      playlist: false,
    ),
    (
      title: 'List.Show.S04E09.mkv',
      query: 'List Show',
      s: 4,
      e: 9,
      playlist: true,
    ),
  ]) {
    testWidgets(
      'identify ${entry.playlist ? 'playlist' : 'dynamic'} ${entry.title} query and available coordinates bypass dialog',
      (t) async {
        final d = IdentifyTitleDriver(t);
        await d.setupIdentity();
        d.metas = [
          IdentifyTitleDriver.identityMeta('Chosen series', type: 'series'),
        ];
        try {
          await d.mountIdentity(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/identify.mp4',
              title: entry.playlist ? 'Ignored fallback' : entry.title,
              contentTitle: 'Ignored content title',
              contentType: 'series',
              contentSeason: 5,
              contentEpisode: 6,
              playlist: entry.playlist
                  ? [
                      PlaylistEntry(
                        url: 'https://player.test/identify.mp4',
                        title: entry.title,
                      ),
                    ]
                  : null,
            ),
          );
          final menu = await d.menu();
          expect(menu.subtitleIdentityLabel, 'Detected: ${entry.query}');
          expect(menu.contentSeason, entry.s);
          expect(menu.contentEpisode, entry.e);
          final pending = d.start(menu);
          await d.found('Chosen series');
          expect(d.catalogQueries, [entry.query]);
          expect(d.searchField.controller.text, entry.query);
          await t.tap(find.text('Chosen series'));
          final result = await d.f.finish(t, pending);
          expect(find.text('Which episode?'), findsNothing);
          expect(result?.season, entry.s);
          expect(result?.episode, entry.e);
          expect(result?.contentType, 'series');
          expect(
            result?.identityLabel,
            'Subtitles for Chosen series S${entry.s}E${entry.e}',
          );
          expect(d.subtitlePaths, [
            '/subtitles/series/tt1200002:${entry.s}:${entry.e}.json',
          ]);
          expect(result?.slots, hasLength(1));
          expect(result?.subtitles, hasLength(1));
          expect(result?.subtitles.single.id, 'identify');
          expect(d.errors, isEmpty);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
  for (final values in [
    ('', ''),
    ('x', '1'),
    ('0', '1'),
    ('-1', '1'),
    ('1', 'x'),
    ('1', '0'),
    ('1', '-1'),
  ]) {
    testWidgets(
      'identify dialog validates empty controllers and ${values.$1}/${values.$2} then accepts trimmed coordinates',
      (t) async {
        final d = IdentifyTitleDriver(t);
        await d.setupIdentity();
        d.metas = [
          IdentifyTitleDriver.identityMeta('Needs episode', type: 'series'),
        ];
        try {
          await d.mountIdentity();
          final pending = d.start(await d.menu());
          await d.found('Needs episode');
          await t.tap(find.text('Needs episode'));
          await d.found('Which episode?');
          final controllers = t
              .widgetList<TextField>(find.byType(TextField))
              .where(
                (w) => ['Season', 'Episode'].contains(w.decoration?.labelText),
              )
              .map((w) => w.controller!)
              .toList();
          expect(controllers.map((c) => c.text), ['', '']);
          await d.episode(values.$1, values.$2);
          expect(
            find.text('Enter a valid season and episode.'),
            findsOneWidget,
          );
          expect(d.subtitlePaths, isEmpty);
          final validSeason = values.$1 == 'x' ? 1 : 3;
          final validEpisode = values.$2 == 'x' ? 1 : 8;
          await d.episode(' $validSeason ', ' $validEpisode ');
          final result = await d.f.finish(t, pending);
          expect(result?.season, validSeason);
          expect(result?.episode, validEpisode);
          expect(d.subtitlePaths, [
            '/subtitles/series/tt1200002:$validSeason:$validEpisode.json',
          ]);
          await d.f.advance(t, const Duration(milliseconds: 350));
          for (final c in controllers) {
            expect(() => c.addListener(() {}), throwsFlutterError);
          }
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
  testWidgets(
    'identify empty title has no detected label or initial search and cancel leaves identity untouched',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      try {
        await d.mountIdentity(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/empty.mp4',
            title: '',
          ),
        );
        final menu = await d.menu();
        expect(menu.subtitleIdentityLabel, isNull);
        final pending = d.start(menu);
        await d.sheet();
        await d.f.actions.settle(t);
        expect(d.catalogQueries, isEmpty);
        expect(d.searchField.controller.text, '');
        expect(d.searchField.autofocus, isTrue);
        expect(find.text('No IMDb-backed results found'), findsNothing);
        final sheet = find
            .ancestor(
              of: find.text('FIX THE TITLE'),
              matching: find.byType(SafeArea),
            )
            .first;
        expect(
          find.descendant(of: sheet, matching: find.byType(ListView)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.descendant(of: sheet, matching: find.byType(ListView)),
            matching: find.byType(InkWell),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: sheet,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsNothing,
        );
        await d.submit('search');
        await d.found('Chosen title');
        await d.dismiss();
        expect(await d.f.finish(t, pending), isNull);
        expect(d.subtitlePaths, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );

  for (final content in ['  Content.Fallback.2025.mp4  ', '   ']) {
    testWidgets(
      'identify blank dynamic title uses content fallback "$content" through the actual tracks caller',
      (t) async {
        final d = IdentifyTitleDriver(t);
        await d.setupIdentity();
        try {
          await d.mountIdentity(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/blank.mp4',
              title: '',
              contentTitle: content,
            ),
          );
          final menu = await d.menu();
          expect(
            menu.subtitleIdentityLabel,
            content.trim().isEmpty ? isNull : 'Detected: Content Fallback',
          );
          final pending = d.start(menu);
          await d.sheet();
          await d.f.actions.settle(t);
          expect(
            d.searchField.controller.text,
            content.trim().isEmpty ? '' : 'Content Fallback',
          );
          expect(
            d.catalogQueries,
            content.trim().isEmpty ? [] : ['Content Fallback'],
          );
          await d.dismiss();
          expect(await d.f.finish(t, pending), isNull);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }

  for (final name in ['  Padded title  ', '   ']) {
    testWidgets(
      'identify manual label trims "$name" or falls back to the detected title while keeping subtitle identity',
      (t) async {
        final d = IdentifyTitleDriver(t);
        await d.setupIdentity();
        d.metas = [IdentifyTitleDriver.identityMeta(name)];
        try {
          await d.mountIdentity();
          final menu = await d.menu();
          final pending = d.start(menu);
          await d.found(name);
          await t.tap(find.text(name));
          final result = await d.f.finish(t, pending);
          expect(result?.imdbId, 'tt1200002');
          expect(result?.identityLabel, 'Subtitles for $name');
          expect(
            d.panel.subtitleIdentityLabel,
            name.trim().isEmpty
                ? 'Detected: Launch Title'
                : 'Subtitles for ${name.trim()}',
          );
          expect(d.subtitlePaths, ['/subtitles/movie/tt1200002.json']);
          expect(d.errors, isEmpty);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }

  testWidgets(
    'identify quick speed menu routes parsed playlist identity into the real subtitle action',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      try {
        await d.mountIdentity(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/quick.mp4',
            title: 'Ignored widget title',
            playlist: [
              PlaylistEntry(
                url: 'https://player.test/quick.mp4',
                title: 'Quick.Show.S02E03.mkv',
              ),
            ],
          ),
        );
        playerControls(t).onSpeed();
        await d.f.advance(t);
        await d.f.advance(t, const Duration(milliseconds: 350));
        expect(d.panel.initialSection.name, 'speed');
        expect(d.panel.contentSeason, 2);
        expect(d.panel.contentEpisode, 3);
        expect(d.panel.subtitleIdentityLabel, 'Detected: Quick Show');
        for (var i = 0; i < 3; i++) {
          await d.f.key(t, LogicalKeyboardKey.arrowUp);
        }
        await d.f.key(t, LogicalKeyboardKey.arrowRight);
        await d.f.key(t, LogicalKeyboardKey.enter);
        await d.found('Chosen title');
        expect(d.catalogQueries, ['Quick Show']);
        await t.tap(find.text('Chosen title'));
        await d.f.until(t, () => d.subtitlePaths.isNotEmpty);
        await d.f.actions.settle(t);
        expect(d.panel.subtitleIdentityLabel, 'Subtitles for Chosen title');
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );

  testWidgets(
    'identify quick caller without a playlist returns normally and reads the current dynamic title',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      try {
        await d.mountIdentity();
        expect(playerControls(t).onSpeed, returnsNormally);
        await d.f.advance(t);
        expect(d.panel.initialSection.name, 'speed');
        expect(d.panel.subtitleIdentityLabel, 'Detected: Launch Title');
        expect(d.panel.hasPlaylist, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'identify movie clears manual coordinates before a later series uses widget coordinates',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      try {
        await d.mountIdentity(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/movie-series.mp4',
            title: 'Unparsed launch',
            contentSeason: 5,
            contentEpisode: 6,
          ),
        );
        var pending = d.start(await d.menu());
        await d.found('Chosen title');
        await t.tap(find.text('Chosen title'));
        final movie = await d.f.finish(t, pending);
        expect(movie?.contentType, 'movie');
        expect(movie?.season, isNull);
        expect(movie?.episode, isNull);
        d.panel.onClose();
        await d.f.advance(t);
        d.metas = [
          IdentifyTitleDriver.identityMeta(
            'Later series',
            id: 'tt1200003',
            type: 'series',
          ),
        ];
        pending = d.start(await d.menu());
        await d.found('Later series');
        await t.tap(find.text('Later series'));
        final series = await d.f.finish(t, pending);
        expect(find.text('Which episode?'), findsNothing);
        expect(series?.season, 5);
        expect(series?.episode, 6);
        expect(d.subtitlePaths, [
          '/subtitles/movie/tt1200002.json',
          '/subtitles/series/tt1200003:5:6.json',
        ]);
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
}
