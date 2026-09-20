import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('random playback retains coordinate-only ordinary IMDb episodes', () {
    for (final catalogId in ['tt123', 'tmdb:123', 'trakt:123']) {
      for (final id in [null, '', '  ']) {
        expect(
          StremioService.randomEpisodeVideoId(
            catalogId: catalogId,
            imdbId: 'tt123',
            season: 2,
            episode: 3,
            videoId: id,
          ),
          'tt123:2:3',
        );
      }
    }
  });

  test('random playback never synthesizes IDs for custom catalogs', () {
    for (final imdbId in [null, 'custom', 'tt123']) {
      expect(
        StremioService.randomEpisodeVideoId(
          catalogId: 'custom',
          imdbId: imdbId,
          season: 2,
          episode: 3,
        ),
        isNull,
      );
    }
    for (final catalogId in ['custom', 'tt123']) {
      expect(
        StremioService.randomEpisodeVideoId(
          catalogId: catalogId,
          imdbId: 'tt123',
          season: 2,
          episode: 3,
          videoId: ' custom-video ',
        ),
        'custom-video',
      );
    }
  });

  test('ordinary playback leaves continuous shuffle off', () {
    final args = TorrentPlaybackService.playerArgsForTesting(
      const PlaybackMeta.catalog(contentType: 'series'),
    );
    expect(args.initialContinuousShuffle, isFalse);
    expect(args.disableExternalPlayer, isFalse);
    expect(args.toWidget().initialContinuousShuffle, isFalse);
  });

  test('continuous choice survives launch copies and Flutter construction', () {
    final args = TorrentPlaybackService.playerArgsForTesting(
      const PlaybackMeta.catalog(
        contentType: 'series',
        initialContinuousShuffle: true,
      ),
    );
    expect(args.initialContinuousShuffle, isTrue);
    expect(args.disableExternalPlayer, isTrue);
    final tracked = args.copyWith(traktScrobble: true, simklScrobble: true);
    expect(tracked.initialContinuousShuffle, isTrue);
    expect(tracked.toWidget().initialContinuousShuffle, isTrue);
  });

  test('source picker season scope retains shuffle intent', () {
    const selection = AdvancedSearchSelection(
      imdbId: 'tt123',
      title: 'Series',
      isSeries: true,
      initialContinuousShuffle: true,
    );
    expect(selection.scopedToSeason(2).initialContinuousShuffle, isTrue);
  });
}
