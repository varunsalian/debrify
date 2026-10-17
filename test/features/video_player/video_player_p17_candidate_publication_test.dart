import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

void main() {
  for (final mode in [
    'new list',
    'source key fallback',
    'identity before key',
  ]) {
    testWidgets(
      'P17 candidate publication uses $mode and exposes the committed source',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final initial = episodeSource('Show.S01E01');
        final old = episodeSource('Show.S01E02');
        // A pinned result can resolve the target while still carrying its old
        // scoped tag. Retention drops it; an equivalent target URL survives.
        final incoming = mode == 'source key fallback'
            ? Torrent.fromJson({
                ...episodeSource('Show.S01E02').toJson(),
                'episode_identifier': 'S01E01',
              })
            : episodeSource('Show.S01E02');
        final validated = <Object>[];
        final resolved = <Object>[];
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: initial.directUrl!,
              title: initial.displayTitle,
              contentType: 'series',
              contentSeason: 1,
              contentEpisode: 1,
              stremioSources: mode == 'new list'
                  ? null
                  : [initial, old, if (mode == 'identity before key') incoming],
              seriesSourceFetcher: SeriesSourceFetcher(
                season: 1,
                episode: 1,
                pinnedDirectCandidates: mode == 'source key fallback'
                    ? (s, e, {onPreferredMissing}) async* {
                        yield incoming;
                      }
                    : null,
                searchEpisodes: (s, e) async => [incoming],
                searchPacks: (s, e) async => [],
                validateCandidate: (s) async {
                  validated.add(s);
                  return mode != 'identity before key' || !identical(s, old);
                },
              ),
              resolveSourceToPlaylist: (s, {canContinue}) async {
                resolved.add(s);
                return [
                  PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
                ];
              },
            ),
          );
          final browser = await d.browser();
          await d.f.finish<dynamic>(
            t,
            d.observe<dynamic>(() => browser.onEpisodeSelected(1, 2)),
          );
          expect(d.opens.last.uri, incoming.directUrl);
          expect(resolved, hasLength(1));
          expect(identical(resolved.single, incoming), isTrue);
          expect(playerControls(t).onShowStremioSources, isNotNull);
          final sheet = await d.sourceSheet();
          if (mode == 'identity before key') {
            expect(sheet.sources, hasLength(2));
            expect(sheet.currentSourceIndex, 1);
            expect(identical(sheet.sources.first, old), isTrue);
            expect(identical(sheet.sources.last, incoming), isTrue);
          } else {
            expect(sheet.sources, hasLength(1));
            expect(sheet.currentSourceIndex, 0);
            expect(
              identical(
                sheet.sources.single,
                mode == 'source key fallback' ? old : incoming,
              ),
              isTrue,
            );
          }
          expect(
            validated.where((s) => identical(s, old)),
            hasLength(mode == 'identity before key' ? 1 : 0),
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
