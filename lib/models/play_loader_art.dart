import 'stremio_addon.dart';

/// The presentation-only extras the Marquee play loader paints: the artwork and
/// meta line the detail page already fetched, carried down to the loader so it
/// stops being the poorest-looking screen in a play.
///
/// Every field is nullable and every consumer must degrade: with no backdrop
/// the loader blurs the poster (exactly what it did before), and with no logo
/// it sets the title as type. Nothing here participates in playback, resume or
/// tracking — it is safe to drop on any path that doesn't have it.
class PlayLoaderArt {
  /// Wide backdrop (`StremioMeta.background`). The Marquee plate.
  final String? backdropUrl;

  /// Title-treatment art (`StremioMeta.logo`), painted in place of the title.
  ///
  /// Not all logo art is keyed for a dark plate — some titles ship
  /// black-on-transparent artwork that would vanish. The loader paints it as-is
  /// and keeps the text title as the fallback when the URL fails to load;
  /// judging luminance would need to decode the image first.
  final String? logoUrl;

  /// Already-formatted display strings — the loader never re-formats.
  final String? yearLabel; // e.g. '2024'
  final String? ratingLabel; // e.g. '8.5'
  final String? runtimeLabel; // e.g. '2h 46m'
  final String? certificate; // e.g. 'PG-13'
  final String? genreLabel; // e.g. 'Sci-Fi · Adventure'

  const PlayLoaderArt({
    this.backdropUrl,
    this.logoUrl,
    this.yearLabel,
    this.ratingLabel,
    this.runtimeLabel,
    this.certificate,
    this.genreLabel,
  });

  /// True when there is nothing worth carrying — callers skip attaching it.
  bool get isEmpty =>
      backdropUrl == null &&
      logoUrl == null &&
      yearLabel == null &&
      ratingLabel == null &&
      runtimeLabel == null &&
      certificate == null &&
      genreLabel == null;

  /// Build from a catalog/detail meta. [certificate] comes from the IMDb
  /// enrichment, which [StremioMeta] does not carry.
  ///
  /// Catalog list items usually lack logo/runtime/rating (the addon only
  /// returns them on `/meta`), so this is a best effort by design: the detail
  /// page re-emits a fuller one once its enrichment lands.
  factory PlayLoaderArt.fromMeta(StremioMeta meta, {String? certificate}) {
    final genres = meta.genres;
    return PlayLoaderArt(
      backdropUrl: _clean(meta.background),
      logoUrl: _clean(meta.logo),
      yearLabel: _clean(meta.year),
      ratingLabel: meta.imdbRating == null
          ? null
          : meta.imdbRating!.toStringAsFixed(1),
      runtimeLabel: _clean(meta.runtimeDisplay),
      certificate: _clean(certificate),
      genreLabel: (genres == null || genres.isEmpty)
          ? null
          // Two is all the meta line has room for on a phone.
          : genres.take(2).join(' · '),
    );
  }

  static String? _clean(String? value) =>
      (value == null || value.trim().isEmpty) ? null : value.trim();
}
