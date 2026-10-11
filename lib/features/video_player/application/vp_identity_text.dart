import 'package:debrify/models/stremio_addon.dart';

String vpNormalisedContentType(String type) =>
    type.toLowerCase() == 'series' ? 'series' : 'movie';

String vpSubtitleSearchDisplayLabel(
  StremioMeta meta, {
  required String contentType,
  int? season,
  int? episode,
}) {
  final year = meta.year?.trim();
  final title = year != null && year.isNotEmpty
      ? '${meta.name} ($year)'
      : meta.name;
  if (contentType == 'series' && season != null && episode != null) {
    return '$title S${season}E$episode';
  }
  return title;
}

List<StremioMeta> vpFilterIdentitySearchResults(List<StremioMeta> metas) {
  final bestByKey = <String, StremioMeta>{};

  for (final meta in metas) {
    final imdbId = meta.effectiveImdbId;
    if (imdbId == null || !imdbId.startsWith('tt')) continue;

    final type = meta.type.toLowerCase();
    if (type != 'movie' && type != 'series') continue;

    final key = '$type:$imdbId';
    final existing = bestByKey[key];
    if (existing == null) {
      bestByKey[key] = meta;
      continue;
    }

    final existingScore =
        (existing.poster != null ? 2 : 0) + (existing.year != null ? 1 : 0);
    final newScore =
        (meta.poster != null ? 2 : 0) + (meta.year != null ? 1 : 0);
    if (newScore > existingScore) {
      bestByKey[key] = meta;
    }
  }

  return bestByKey.values.toList(growable: false);
}

String? vpNormalisePosterUrl(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  if (url.startsWith('//')) return 'https:$url';
  return url;
}

String vpIdentityMetaSubtitle(StremioMeta meta) {
  final parts = <String>[
    meta.type.toLowerCase() == 'series' ? 'Series' : 'Movie',
    if (meta.year != null && meta.year!.trim().isNotEmpty) meta.year!,
    if (meta.sourceAddon?.name.trim().isNotEmpty == true)
      meta.sourceAddon!.name,
  ];
  return parts.join(' | ');
}
