import '../models/metadata_preferences.dart';
import '../models/stremio_addon.dart';
import 'metadata_details_service.dart';
import 'metadata_preferences_service.dart';
import 'stremio_service.dart';
import 'tmdb_metadata_repository.dart';
import 'trakt/trakt_episode_model.dart';
import 'tvmaze_service.dart';

class MetadataEpisodeService {
  MetadataEpisodeService({TmdbMetadataRepository? repository})
    : repository = repository ?? TmdbMetadataRepository.instance;
  static final instance = MetadataEpisodeService();
  final TmdbMetadataRepository repository;

  Future<TraktSeason> present(
    StremioMeta show,
    TraktSeason original, {
    MetadataPreferences? preferences,
  }) async {
    final prefs = preferences ?? await MetadataPreferencesService.load();
    final info = prefs.provider(MetadataCategory.episodeInformation);
    final art = prefs.provider(MetadataCategory.episodeArtwork);
    if (info == MetadataPreferences.current &&
        art == MetadataPreferences.current) {
      return original;
    }
    final sources = <String, Map<int, Map<String, dynamic>>>{};
    for (final provider in {info, art}) {
      if (provider == MetadataPreferences.current) continue;
      try {
        List<Map<String, dynamic>> rows = [];
        if (provider == MetadataPreferences.tmdb) {
          final id = await repository.identify(show);
          if (id == null || id.type != 'tv') continue;
          final data = await repository.get(
            'tv/${id.id}/season/${original.number}',
            {'language': prefs.language},
          );
          rows = MetadataDetailsService.maps(data['episodes']);
          if (info == MetadataPreferences.tmdb &&
              prefs.fallback &&
              !prefs.language.toLowerCase().startsWith('en') &&
              original.episodes.any(
                (episode) => !rows.any(
                  (row) =>
                      row['episode_number'] == episode.number &&
                      MetadataDetailsService.text(row['overview']) != null,
                ),
              )) {
            // A failed secondary language read must not discard usable
            // translated fields or artwork from the first response.
            try {
              final english = await repository.get(
                'tv/${id.id}/season/${original.number}',
                {'language': 'en-US'},
              );
              final fallbackRows = {
                for (final row in MetadataDetailsService.maps(
                  english['episodes'],
                ))
                  if (row['episode_number'] is int &&
                      row['season_number'] == original.number)
                    row['episode_number'] as int: row,
              };
              final translated = {
                for (final row in rows)
                  if (row['episode_number'] is int &&
                      row['season_number'] == original.number)
                    row['episode_number'] as int: row,
              };
              rows = [
                for (final number in {...translated.keys, ...fallbackRows.keys})
                  {
                    ...?translated[number],
                    'season_number': original.number,
                    'episode_number': number,
                    for (final field in ['name', 'overview'])
                      field:
                          MetadataDetailsService.text(
                            translated[number]?[field],
                          ) ??
                          fallbackRows[number]?[field],
                  },
              ];
            } catch (_) {}
          }
        } else if (provider == MetadataPreferences.tvmaze) {
          final imdb = show.effectiveImdbId;
          if (imdb == null) continue;
          final found = await TVMazeService.lookupByImdbId(imdb);
          final id = found?['id'];
          if (id is! int) continue;
          rows = await TVMazeService.getEpisodes(id);
        } else if (provider.startsWith(MetadataPreferences.addonPrefix)) {
          final addons = await StremioService.instance.getEnabledAddons();
          final selected = addons.where(
            (a) =>
                '${MetadataPreferences.addonPrefix}${StremioService.metadataProviderValue(a)}' ==
                provider,
          );
          if (selected.isEmpty) continue;
          rows =
              await StremioService.instance.fetchSeriesMeta(
                selected.first,
                show.effectiveImdbId ?? show.id,
              ) ??
              [];
        }
        sources[provider] = {
          for (final row in rows)
            if ((row['season_number'] ?? row['season']) == original.number &&
                (row['episode_number'] ?? row['number'] ?? row['episode'])
                    is int)
              (row['episode_number'] ?? row['number'] ?? row['episode']) as int:
                  row,
        };
      } catch (_) {}
    }
    return TraktSeason(
      number: original.number,
      episodeCount: original.episodeCount,
      episodes: [
        for (final ep in original.episodes)
          _episode(
            ep,
            sources[info]?[ep.number],
            sources[art]?[ep.number],
            prefs,
          ),
      ],
    );
  }

  static TraktEpisode _episode(
    TraktEpisode original,
    Map<String, dynamic>? info,
    Map<String, dynamic>? art,
    MetadataPreferences prefs,
  ) {
    // Overlay known entries only; never add/reorder episodes or change IDs.
    final image = art?['image'];
    final thumbnail =
        TmdbMetadataRepository.image(art?['still_path'], size: 'w300') ??
        MetadataDetailsService.text(art?['thumbnail']) ??
        (image is Map
            ? MetadataDetailsService.text(image['medium'] ?? image['original'])
            : null);
    return TraktEpisode(
      season: original.season,
      number: original.number,
      title:
          MetadataDetailsService.text(info?['name'] ?? info?['title']) ??
          original.title,
      overview:
          MetadataDetailsService.text(
            info?['overview'] ?? info?['description'],
          ) ??
          (prefs.provider(MetadataCategory.episodeInformation) ==
                      MetadataPreferences.current ||
                  prefs.fallback
              ? original.overview
              : null),
      thumbnailUrl:
          thumbnail ??
          (prefs.provider(MetadataCategory.episodeArtwork) ==
                      MetadataPreferences.current ||
                  prefs.fallback
              ? original.thumbnailUrl
              : null),
      imdbId: original.imdbId,
      rating: original.rating,
      firstAired: original.firstAired,
      runtime: original.runtime,
      playbackUrl: original.playbackUrl,
    );
  }
}
