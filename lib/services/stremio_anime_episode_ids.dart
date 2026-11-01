import '../models/media_identity.dart';

final _animeEpisodeId = RegExp(r'^((?:mal|anilist|anidb):[0-9]+):([0-9]+)$');

/// Names anime episodes by their IMDb coordinate when the meta's own
/// numbering is the IMDb show's.
///
/// AIOMetadata's TVDB and TMDB layouts (anime ID provider MAL) give each
/// episode a per-cour `mal:<id>:<n>` ID but number it by the show's seasons,
/// and stamp the show's IMDb ID. Torrentio, Comet, the built-in scrapers and
/// the trackers only know `tt…:S:E`, so those episodes found no sources.
///
/// The numbering counts as the show's only with evidence: regular episodes
/// span more than one season, or a single season holds one cour whose IDs
/// count its episodes the same way and either a regular episode already carries
/// its own plain `tt…:S:E` ID (AIOMetadata's fallback for unmapped episodes) or
/// AIOMetadata names a show-wide layout (`_metaProvider` tvdb/tmdb/imdb). A
/// single season holding several cours may be absolute order, so it stays as
/// it is, as do AIOMetadata's MAL and Kitsu layouts, which number each cour from
/// season 1, and any list whose `tt…` IDs disagree with their own numbering or
/// whose episodes would share a coordinate. Specials are neither renamed nor
/// evidence: AIOMetadata's show-wide layouts already name every one `tt…:0:N`,
/// which says nothing about the regular episodes. `kitsu:` IDs (Torrentio and
/// Comet take them) and `tmdb:` IDs (AIOMetadata's fallback exactly when the
/// IMDb episode is unknown) are never renamed.
List<Map<String, dynamic>> withImdbAnimeEpisodeIds(
  Map<String, dynamic> meta,
  List<Map<String, dynamic>> videos,
) {
  final provider = meta['_metaProvider'];
  if (provider == 'mal' || provider == 'kitsu') return videos;
  final imdb = [
    meta['imdb_id'],
    meta['_imdbId'],
  ].whereType<String>().map((id) => id.trim()).where(MediaIdentity.isImdb);
  if (imdb.isEmpty) return videos;
  final imdbId = imdb.first;
  final imdbEpisode = RegExp('^$imdbId:([0-9]+):([0-9]+)\$');
  final seasons = <int>{};
  final cours = <String>{};
  var imdbNumbered = false;
  var courNumbered = true;
  final coordinates = <(int, int)>{};
  for (final video in videos) {
    final (season, episode) = _coordinate(video);
    if (season == null || episode == null || season < 0) continue;
    if (!coordinates.add((season, episode))) return videos;
    final id = video['id']?.toString() ?? '';
    if (imdbEpisode.firstMatch(id) case final match?) {
      if (int.tryParse(match[1]!) != season ||
          int.tryParse(match[2]!) != episode) {
        return videos;
      }
      if (season > 0) imdbNumbered = true;
    }
    if (season == 0) continue;
    seasons.add(season);
    if (_animeEpisodeId.firstMatch(id) case final match?) {
      cours.add(match[1]!);
      if (int.tryParse(match[2]!) != episode) courNumbered = false;
    }
  }
  final showWide =
      seasons.length >= 2 ||
      (cours.length <= 1 &&
          courNumbered &&
          (imdbNumbered || const {'tvdb', 'tmdb', 'imdb'}.contains(provider)));
  if (!showWide) return videos;
  return [
    for (final video in videos)
      switch (_coordinate(video)) {
        (final int season, final int episode)
            when season >= 1 &&
                _animeEpisodeId.hasMatch(video['id']?.toString() ?? '') =>
          {...video, 'id': '$imdbId:$season:$episode'},
        _ => video,
      },
  ];
}

(int?, int?) _coordinate(Map<String, dynamic> video) =>
    (_int(video['season']), _int(video['number'] ?? video['episode']));

int? _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

/// A catalog show in an anime scheme that carries an IMDb ID: its episodes
/// may be renamed above, so a custom identity stored for it is checked again.
bool mayHaveImdbAnimeEpisodes(String catalogId, String imdbId) =>
    MediaIdentity.isImdb(imdbId) &&
    RegExp(r'^(?:mal|anilist|anidb):[0-9]+$').hasMatch(catalogId);
