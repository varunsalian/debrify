import '../../models/stremio_addon.dart';
import 'spotlight_board.dart';

/// Reuses immutable catalog presentation across unrelated Home rebuilds.
/// Weak keys keep this cache tied to the lifetime of the loaded metadata,
/// rather than retaining every catalog visited during a long TV session.
class SpotlightCatalogCardCache {
  SpotlightCatalogCardCache({required this.wideArtwork, required this.onOpen});

  final String? Function(StremioMeta) wideArtwork;
  final void Function(StremioMeta, StremioAddon) onOpen;
  final _cards =
      Expando<
        ({
          bool landscape,
          StremioAddon addon,
          String? imdbId,
          SpotlightCard card,
        })
      >();

  SpotlightCard resolve(
    StremioMeta item,
    StremioAddon addon, {
    required bool landscape,
  }) {
    final imdbId = item.effectiveImdbId;
    final previous = _cards[item];
    if (previous != null &&
        previous.landscape == landscape &&
        identical(previous.addon, addon) &&
        previous.imdbId == imdbId) {
      return previous.card;
    }
    final card = SpotlightCard(
      metadata: item,
      image: landscape ? wideArtwork(item) : item.poster,
      fallbackImage: landscape ? item.poster : null,
      title: item.name,
      rating: item.imdbRating,
      shape: landscape ? SpotlightCardShape.wide : SpotlightCardShape.poster,
      watchedImdbId: item.type == 'movie' || item.type == 'series'
          ? (imdbId ?? item.id)
          : null,
      watchedContentType: item.type,
      // Capture provenance, never a row index that can change after inserts.
      onOpen: () => onOpen(item, addon),
    );
    _cards[item] = (
      landscape: landscape,
      addon: addon,
      imdbId: imdbId,
      card: card,
    );
    return card;
  }
}
