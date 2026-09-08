import 'dart:async';
import 'dart:collection';
import 'metadata_details_service.dart';
import 'stremio_service.dart';
import '../models/metadata_preferences.dart';
import '../models/stremio_addon.dart';
import 'metadata_preferences_service.dart';
import 'tmdb_metadata_repository.dart';

class MetadataPresentation {
  const MetadataPresentation(
    this.item, {
    this.unavailable = const {},
    this.retryable = false,
  });
  final bool retryable;
  final StremioMeta item;
  final Set<MetadataCategory> unavailable;
}

typedef MetadataAddonLoader =
    Future<StremioMeta?> Function(String provider, StremioMeta item);

/// Changes presentation fields only. The input remains authoritative for media
/// identity, stream source, IMDb rating and all user/tracker timestamps.
class MetadataProviderService {
  MetadataProviderService({
    TmdbMetadataRepository? tmdb,
    MetadataAddonLoader? addonLoader,
  }) : tmdb = tmdb ?? TmdbMetadataRepository.instance,
       addonLoader = addonLoader ?? _loadAddon;

  static final instance = MetadataProviderService();
  static Future<StremioMeta?> _loadAddon(
    String provider,
    StremioMeta item,
  ) async {
    final imdb = item.effectiveImdbId ?? item.id;
    if (imdb.isEmpty) return null;
    final result = await StremioService.instance.fetchMetaDetails(
      imdbId: imdb,
      type: item.type,
      providerOverride: provider.substring(
        MetadataPreferences.addonPrefix.length,
      ),
    );
    if (result == null ||
        result.type != item.type ||
        (result.effectiveImdbId != imdb && result.id != imdb)) {
      return null;
    }
    return result;
  }

  final TmdbMetadataRepository tmdb;
  final MetadataAddonLoader? addonLoader;

  /// Custom detail layouts paint their own recommendation tiles. Publish small
  /// ordered batches after the initial rail, using the same presentation policy
  /// as ordinary catalog tiles without delaying the detail screen.
  Stream<List<StremioMeta>> presentBatches(
    List<StremioMeta> items, {
    required bool Function() isRelevant,
    MetadataPreferences? preferences,
  }) async* {
    final prefs = preferences ?? await MetadataPreferencesService.load();
    if (const [
      MetadataCategory.information,
      MetadataCategory.posters,
      MetadataCategory.backgrounds,
    ].every((c) => prefs.provider(c) == MetadataPreferences.current)) {
      return;
    }
    final result = List<StremioMeta>.of(items);
    for (var offset = 0; offset < items.length; offset += 4) {
      if (!isRelevant()) return;
      final batch = await Future.wait(
        items
            .skip(offset)
            .take(4)
            .map(
              (item) =>
                  present(item, preferences: prefs, isRelevant: isRelevant),
            ),
      );
      if (!isRelevant()) return;
      for (var i = 0; i < batch.length; i++) {
        result[offset + i] = batch[i].item;
      }
      yield List<StremioMeta>.unmodifiable(result);
    }
  }

  final _addonWaiters = Queue<Completer<void>>();
  int _activeAddons = 0;
  Future<StremioMeta?> _boundedAddon(
    String provider,
    StremioMeta item,
    bool Function()? relevant,
  ) async {
    if (_addonWaiters.length >= 128) return null;
    if (_activeAddons >= 4) {
      final ready = Completer<void>();
      _addonWaiters.add(ready);
      await ready.future;
    } else {
      _activeAddons++;
    }
    try {
      if (relevant != null && !relevant()) return null;
      return await addonLoader?.call(provider, item);
    } finally {
      if (_addonWaiters.isNotEmpty) {
        _addonWaiters.removeFirst().complete();
      } else {
        _activeAddons--;
      }
    }
  }

  Future<MetadataPresentation> present(
    StremioMeta item, {
    MetadataPreferences? preferences,
    bool Function()? isRelevant,
  }) async {
    if (item.type != 'movie' && item.type != 'series') {
      return MetadataPresentation(item);
    }
    final prefs = preferences ?? await MetadataPreferencesService.load();
    const categories = {
      MetadataCategory.information,
      MetadataCategory.posters,
      MetadataCategory.backgrounds,
    };
    if (categories.every(
      (c) => prefs.provider(c) == MetadataPreferences.current,
    )) {
      return MetadataPresentation(item);
    }
    final sources = <String, StremioMeta?>{};
    var retryable = false;
    final needed = categories
        .map(prefs.provider)
        .where((p) => p != MetadataPreferences.current)
        .toSet();
    await Future.wait(
      needed.map((provider) async {
        if (isRelevant != null && !isRelevant()) return;
        try {
          if (provider == MetadataPreferences.tmdb) {
            final identity = await tmdb.identify(item, isRelevant: isRelevant);
            if (identity != null) {
              final imageLanguage = prefs.artworkLanguage == 'same'
                  ? prefs.language.split('-').first
                  : prefs.artworkLanguage;
              final data = await tmdb.details(
                identity,
                language: prefs.language,
                imageLanguage: imageLanguage == 'original'
                    ? 'null'
                    : imageLanguage.split('-').first,
                append: 'images',
                isRelevant: isRelevant,
              );
              if (prefs.fallback &&
                  !prefs.language.startsWith('en') &&
                  prefs.provider(MetadataCategory.information) ==
                      MetadataPreferences.tmdb &&
                  ((data['overview'] is! String) ||
                      (data['overview'] as String).trim().isEmpty)) {
                try {
                  final english = await tmdb.get(
                    '${identity.type}/${identity.id}',
                    {'language': 'en-US'},
                    isRelevant,
                  );
                  for (final field in ['title', 'name', 'overview']) {
                    if (data[field] is! String ||
                        (data[field] as String).trim().isEmpty) {
                      data[field] = english[field];
                    }
                  }
                } catch (_) {
                  retryable = true;
                }
              }
              if (prefs.artworkLanguage == 'original' &&
                  data['original_language'] is String &&
                  (prefs.provider(MetadataCategory.posters) ==
                          MetadataPreferences.tmdb ||
                      prefs.provider(MetadataCategory.backgrounds) ==
                          MetadataPreferences.tmdb)) {
                try {
                  data['images'] = await tmdb.get(
                    '${identity.type}/${identity.id}/images',
                    {
                      'include_image_language':
                          '${data['original_language']},null${prefs.fallback ? ',en' : ''}',
                    },
                    isRelevant,
                  );
                } catch (_) {
                  retryable = true;
                }
              }
              sources[provider] = fromTmdb(item, data, prefs);
            }
          } else if (provider.startsWith(MetadataPreferences.addonPrefix)) {
            sources[provider] = await _boundedAddon(provider, item, isRelevant);
          }
        } catch (_) {
          retryable = true;
          // Preserve the usable initial display; callers can show the explicit
          // unavailable-category state rather than blocking the entire page.
        }
      }),
    );
    final missing = <MetadataCategory>{};
    StremioMeta? selected(MetadataCategory category) {
      final provider = prefs.provider(category);
      if (provider == MetadataPreferences.current) return item;
      final value = sources[provider];
      if (value == null) missing.add(category);
      return value;
    }

    final info = selected(MetadataCategory.information);
    final posters = selected(MetadataCategory.posters);
    final art = selected(MetadataCategory.backgrounds);
    if (prefs.provider(MetadataCategory.posters) !=
            MetadataPreferences.current &&
        posters?.poster == null) {
      missing.add(MetadataCategory.posters);
    }
    if (prefs.provider(MetadataCategory.backgrounds) !=
            MetadataPreferences.current &&
        art?.background == null &&
        art?.logo == null) {
      missing.add(MetadataCategory.backgrounds);
    }
    if (prefs.provider(MetadataCategory.information) !=
            MetadataPreferences.current &&
        (info?.description?.isEmpty ?? true)) {
      missing.add(MetadataCategory.information);
    }
    String? text(String? value, String? previous) =>
        value != null && value.trim().isNotEmpty
        ? value
        : (prefs.fallback ? previous : null);
    return MetadataPresentation(
      StremioMeta(
        id: item.id,
        imdbId: item.imdbId,
        type: item.type,
        name: text(info?.name, item.name) ?? item.name,
        description: text(info?.description, item.description),
        poster: text(posters?.poster, item.poster),
        background: text(art?.background, item.background),
        logo: text(art?.logo, item.logo),
        trailerYtId: item.trailerYtId,
        genres: info?.genres?.isNotEmpty == true
            ? info!.genres
            : (prefs.fallback ? item.genres : null),
        runtime: text(info?.runtime, item.runtime),
        year: item.year,
        imdbRating: item.imdbRating,
        addedAtMs: item.addedAtMs,
        sourceAddon: item.sourceAddon,
      ),
      unavailable: Set.unmodifiable(missing),
      retryable: retryable,
    );
  }

  Future<List<MetadataTrailer>> trailers(
    StremioMeta item,
    Future<String?> Function() current, {
    MetadataPreferences? preferences,
  }) async {
    final prefs = preferences ?? await MetadataPreferencesService.load();
    final provider = prefs.provider(MetadataCategory.trailers);
    Future<List<MetadataTrailer>> original() async {
      final key = await current();
      return key == null || key.isEmpty
          ? []
          : [
              MetadataTrailer(
                key: key,
                title: 'Trailer',
                language: '',
                type: 'Trailer',
                official: false,
              ),
            ];
    }

    if (provider == MetadataPreferences.current) return original();
    try {
      if (provider == MetadataPreferences.tmdb) {
        final result = await MetadataDetailsService(
          repository: tmdb,
        ).trailers(item, preferences: prefs);
        if (result.isNotEmpty) return result;
      } else if (provider.startsWith(MetadataPreferences.addonPrefix)) {
        final meta = await addonLoader?.call(provider, item);
        final key = meta?.trailerYtId;
        if (key != null && key.isNotEmpty) {
          return [
            MetadataTrailer(
              key: key,
              title: 'Trailer',
              language: '',
              type: 'Trailer',
              official: false,
            ),
          ];
        }
      }
    } catch (_) {}
    return prefs.fallback ? original() : [];
  }

  static StremioMeta fromTmdb(
    StremioMeta base,
    Map<String, dynamic> data,
    MetadataPreferences prefs,
  ) {
    String? string(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    final images = data['images'];
    final logos = images is Map ? images['logos'] : null;
    String? logo;
    if (logos is List) {
      final lang = switch (prefs.artworkLanguage) {
        'same' => prefs.language.split('-').first,
        'original' => string(data['original_language']) ?? 'en',
        _ => prefs.artworkLanguage.split('-').first,
      };
      for (final candidateLanguage in [lang, null, if (prefs.fallback) 'en']) {
        for (final raw in logos) {
          if (raw is! Map || raw['iso_639_1'] != candidateLanguage) continue;
          logo = TmdbMetadataRepository.image(raw['file_path']);
          if (logo != null) break;
        }
        if (logo != null) break;
      }
    }
    String? artwork(String kind, String fallbackField, String size) {
      final rows = images is Map ? images[kind] : null;
      final lang = switch (prefs.artworkLanguage) {
        'same' => prefs.language.split('-').first,
        'original' => string(data['original_language']) ?? 'en',
        _ => prefs.artworkLanguage.split('-').first,
      };
      if (rows is List) {
        for (final language in [lang, null, if (prefs.fallback) 'en']) {
          for (final row in rows) {
            if (row is! Map || row['iso_639_1'] != language) continue;
            final url = TmdbMetadataRepository.image(
              row['file_path'],
              size: size,
            );
            if (url != null) return url;
          }
        }
      }
      return rows == null || prefs.fallback
          ? TmdbMetadataRepository.image(data[fallbackField], size: size)
          : null;
    }

    final genres = data['genres'];
    final episodeRuntime = data['episode_run_time'];
    final runtime =
        data['runtime'] ??
        (episodeRuntime is List
            ? episodeRuntime
                  .whereType<num>()
                  .where((n) => n.isFinite && n > 0)
                  .firstOrNull
            : null);
    return StremioMeta(
      id: base.id,
      imdbId: base.imdbId,
      type: base.type,
      name: string(data['title']) ?? string(data['name']) ?? base.name,
      description: string(data['overview']),
      poster: artwork('posters', 'poster_path', 'w500'),
      background: artwork('backdrops', 'backdrop_path', 'w1280'),
      logo: logo,
      genres: genres is List
          ? [
              for (final g in genres)
                if (g is Map && string(g['name']) != null) string(g['name'])!,
            ]
          : null,
      runtime: runtime is num && runtime.isFinite && runtime > 0
          ? '${runtime.toInt()} min'
          : null,
    );
  }
}
