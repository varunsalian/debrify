import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/identity_fixture.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

Map<String, Object?> meta(
  String name, {
  String id = 'tt0900001',
  String type = 'movie',
  String? poster,
  String? year,
}) => {
  'id': name,
  'imdb_id': id,
  'name': name,
  'type': type,
  if (poster != null) 'poster': poster,
  if (year != null) 'year': year,
};

void main() {
  testWidgets(
    'empty identity catalog leaves identity unset and shows empty results',
    (tester) async {
      final fixture = VideoPlayerEnvironment();
      await tester.runAsync(fixture.initialize);
      await installIdentityCatalog(tester, fixture, metas: []);
      try {
        await fixture.mount(
          tester,
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/empty.mp4',
            title: 'Unknown',
          ),
        );
        final menu = await openPlayerMenu(tester, fixture);
        final result = menu.onIdentifyTitle!();
        await fixture.until(
          tester,
          () => find.text('No IMDb-backed results found').evaluate().isNotEmpty,
        );
        expect(find.text('No IMDb-backed results found'), findsOneWidget);
        expect(menu.contentImdbId, isNull);
        fixture.navigator.currentState!.pop();
        expect(await fixture.finish(tester, result), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );
  for (final year in ['2025', '   ']) {
    testWidgets(
      'identity year presence improves equally illustrated duplicate "$year"',
      (tester) async {
        final fixture = VideoPlayerEnvironment();
        await tester.runAsync(fixture.initialize);
        await installIdentityCatalog(
          tester,
          fixture,
          metas: [
            meta('No year loser', poster: '//player.test/poster.png'),
            meta(
              'Year presence winner',
              poster: '//player.test/poster.png',
              year: year,
            ),
          ],
        );
        try {
          await fixture.mount(
            tester,
            const VideoPlayerScreen(
              videoUrl: 'https://player.test/year.mp4',
              title: 'Unknown',
            ),
          );
          final menu = await openPlayerMenu(tester, fixture);
          final result = menu.onIdentifyTitle!();
          await fixture.until(
            tester,
            () => find.text('Year presence winner').evaluate().isNotEmpty,
          );
          expect(find.text('No year loser'), findsNothing);
          await tester.tap(find.text('Year presence winner'));
          expect(
            (await fixture.finish(tester, result))?.identityLabel,
            year.trim().isEmpty
                ? 'Subtitles for Year presence winner'
                : 'Subtitles for Year presence winner (2025)',
          );
        } finally {
          await fixture.close(tester);
        }
      },
    );
  }
  for (final year in <String?>[null, '   ', ' 2025 ']) {
    testWidgets(
      'movie identity adopts without episode prompt for year "$year"',
      (tester) async {
        final fixture = VideoPlayerEnvironment();
        await tester.runAsync(fixture.initialize);
        await installIdentityCatalog(
          tester,
          fixture,
          metas: [
            meta('Chosen film', type: 'MOVIE', year: year, poster: '   '),
          ],
          addonName: ' ',
        );
        try {
          await fixture.mount(
            tester,
            const VideoPlayerScreen(
              videoUrl: 'https://player.test/movie.mp4',
              title: 'Unknown movie',
            ),
          );
          final menu = await openPlayerMenu(tester, fixture);
          final result = menu.onIdentifyTitle!();
          await fixture.until(
            tester,
            () => find.text('Chosen film').evaluate().isNotEmpty,
          );
          final expectedSubtitle = year?.trim().isNotEmpty == true
              ? 'Movie | $year'
              : 'Movie';
          expect(find.text(expectedSubtitle), findsOneWidget);
          expect(
            tester
                .widgetList<Image>(find.byType(Image))
                .where((image) => image.image is NetworkImage),
            isEmpty,
          );
          await tester.tap(find.text('Chosen film'));
          await fixture.advance(tester, const Duration(milliseconds: 350));
          expect(find.text('Which episode?'), findsNothing);
          final accepted = await fixture.finish(tester, result);
          expect(accepted, isNotNull);
          expect(accepted!.contentType, 'movie');
          expect(accepted.imdbId, 'tt0900001');
          expect(accepted.season, isNull);
          expect(accepted.episode, isNull);
          final title = year?.trim().isNotEmpty == true
              ? 'Chosen film (${year!.trim()})'
              : 'Chosen film';
          expect(accepted.identityLabel, 'Subtitles for $title');
          await fixture.advance(tester, const Duration(milliseconds: 300));
          expect(
            tester
                .widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel))
                .subtitleIdentityLabel,
            'Subtitles for $title',
          );
        } finally {
          await fixture.close(tester);
        }
      },
    );
  }

  testWidgets(
    'identity search rejects custom series ids and keeps type namespaces',
    (tester) async {
      final fixture = VideoPlayerEnvironment();
      await tester.runAsync(fixture.initialize);
      await installIdentityCatalog(
        tester,
        fixture,
        metas: [
          meta(
            'Custom identity',
            id: const CustomSeriesIdentity('addon', 'catalog').id,
            type: 'series',
          ),
          meta('Movie namespace'),
          meta('Series namespace', type: 'series'),
          meta('Unsupported kind', id: 'tt0900002', type: 'tv'),
        ],
      );
      try {
        await fixture.mount(
          tester,
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/filter.mp4',
            title: 'Unknown',
          ),
        );
        final menu = await openPlayerMenu(tester, fixture);
        final result = menu.onIdentifyTitle!();
        await fixture.until(
          tester,
          () => find.text('Movie namespace').evaluate().isNotEmpty,
        );
        expect(find.text('Custom identity'), findsNothing);
        expect(find.text('Unsupported kind'), findsNothing);
        expect(find.text('Series namespace'), findsOneWidget);
        expect(
          tester
              .widgetList<Image>(find.byType(Image))
              .where((image) => image.image is NetworkImage),
          isEmpty,
        );
        await tester.tap(find.text('Movie namespace'));
        expect((await fixture.finish(tester, result))?.contentType, 'movie');
      } finally {
        await fixture.close(tester);
      }
    },
  );

  for (final reverse in [false, true]) {
    testWidgets(
      'identity duplicate ranking prefers poster over year in ${reverse ? 'reverse' : 'forward'} order',
      (tester) async {
        final fixture = VideoPlayerEnvironment();
        await tester.runAsync(fixture.initialize);
        final candidates = [
          meta('Poster winner', poster: 'https://player.test/winner.png'),
          meta('Year loser', year: '2024'),
        ];
        await installIdentityCatalog(
          tester,
          fixture,
          metas: reverse ? candidates.reversed.toList() : candidates,
        );
        try {
          await fixture.mount(
            tester,
            const VideoPlayerScreen(
              videoUrl: 'https://player.test/rank.mp4',
              title: 'Unknown',
            ),
          );
          final menu = await openPlayerMenu(tester, fixture);
          final result = menu.onIdentifyTitle!();
          await fixture.until(
            tester,
            () => find.text('Poster winner').evaluate().isNotEmpty,
          );
          expect(find.text('Year loser'), findsNothing);
          await tester.tap(find.text('Poster winner'));
          expect(
            (await fixture.finish(tester, result))?.identityLabel,
            'Subtitles for Poster winner',
          );
        } finally {
          await fixture.close(tester);
        }
      },
    );
  }

  for (final year in <String?>[null, '2024']) {
    testWidgets(
      year == null
          ? 'identity zero scores keep first title and original result order'
          : 'identity equal scores keep first title and original result order',
      (tester) async {
        final fixture = VideoPlayerEnvironment();
        await tester.runAsync(fixture.initialize);
        await installIdentityCatalog(
          tester,
          fixture,
          metas: [
            meta('First winner', type: 'MOVIE', year: year),
            meta('Second result', id: 'tt0900002'),
            meta('Later tie', year: year == null ? null : '2025'),
          ],
        );
        try {
          await fixture.mount(
            tester,
            const VideoPlayerScreen(
              videoUrl: 'https://player.test/tie.mp4',
              title: 'Unknown',
            ),
          );
          final menu = await openPlayerMenu(tester, fixture);
          final result = menu.onIdentifyTitle!();
          await fixture.until(
            tester,
            () => find.text('First winner').evaluate().isNotEmpty,
          );
          expect(find.text('Later tie'), findsNothing);
          expect(
            tester.getTopLeft(find.text('First winner')).dy,
            lessThan(tester.getTopLeft(find.text('Second result')).dy),
          );
          await tester.tap(find.text('First winner'));
          expect(
            (await fixture.finish(tester, result))?.identityLabel,
            year == null
                ? 'Subtitles for First winner'
                : 'Subtitles for First winner (2024)',
          );
        } finally {
          await fixture.close(tester);
        }
      },
    );
  }
  for (final poster in ['http://player.test/absolute.png', '/relative.png']) {
    testWidgets(
      poster.startsWith('http')
          ? 'series identity reuses launch episode and keeps absolute poster URL'
          : 'series identity preserves a single-slash poster URL',
      (tester) async {
        final fixture = VideoPlayerEnvironment();
        await tester.runAsync(fixture.initialize);
        await installIdentityCatalog(
          tester,
          fixture,
          metas: [meta('Known series', type: 'series', poster: poster)],
        );
        try {
          await fixture.mount(
            tester,
            const VideoPlayerScreen(
              videoUrl: 'https://player.test/known.mp4',
              title: 'Unknown',
              contentSeason: 12,
              contentEpisode: 34,
            ),
          );
          final menu = await openPlayerMenu(tester, fixture);
          final result = menu.onIdentifyTitle!();
          await fixture.until(
            tester,
            () => find.text('Known series').evaluate().isNotEmpty,
          );
          expect(
            tester
                .widgetList<Image>(find.byType(Image))
                .map((image) => image.image)
                .whereType<NetworkImage>()
                .map((image) => image.url),
            contains(poster),
          );
          await tester.tap(find.text('Known series'));
          final accepted = await fixture.finish(tester, result);
          expect(find.text('Which episode?'), findsNothing);
          expect(accepted?.season, 12);
          expect(accepted?.episode, 34);
          expect(accepted?.identityLabel, 'Subtitles for Known series S12E34');
        } finally {
          await fixture.close(tester);
        }
      },
    );
  }
}
