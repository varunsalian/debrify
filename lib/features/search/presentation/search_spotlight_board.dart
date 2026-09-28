import 'package:flutter/widgets.dart';
import '../../../models/stremio_addon.dart';
import '../../../widgets/home/spotlight_board.dart';
import '../../home/application/home_stage_metadata.dart';
import 'catalog_search_status.dart';

/// Search's shelves-only Spotlight view. The supplied section snapshot anchors
/// callbacks to their original section even when more catalogs arrive later.
Widget buildSearchSpotlightBoard({
  required BuildContext context,
  required List<CatalogSection> sections,
  required List<List<FocusNode>> rowNodes,
  required Key boardKey,
  required FocusNode heroNode,
  required String query,
  required bool searching,
  required int failures,
  required bool landscape,
  required bool showCardTitlesAndRatings,
  required bool expandFocusedCard,
  required bool trailersEnabled,
  required double trailerVolume,
  required VoidCallback onExitTop,
  required VoidCallback onTrailerStop,
  required void Function(StremioMeta, StremioAddon) onHeroOpen,
  required void Function(CatalogSection, StremioMeta) onOpen,
  required void Function(StremioMeta, StremioAddon)? onPlay,
  required String? Function(CatalogSection) sourceTag,
  required void Function(CatalogSection) onSeeAll,
  required void Function(CatalogSection) onLoadMore,
}) {
  return Column(
    children: [
      // Reserve the status strip so completion never shifts focused cards.
      if (searching || failures > 0)
        buildCatalogSearchStatus(
          context,
          searching: searching,
          failures: failures,
        )
      else
        const SizedBox(height: 16),
      Expanded(
        child: SpotlightBoard(
          key: boardKey,
          hero: const [],
          heroNode: heroNode,
          heroAddon: null,
          onHeroOpen: onHeroOpen,
          shelvesOnly: true,
          dpad: true,
          showCardTitlesAndRatings: showCardTitlesAndRatings,
          forceCardParallax: true,
          onExitTop: onExitTop,
          expandFocusedCard: expandFocusedCard,
          trailersEnabled: trailersEnabled,
          cardTrailerVolume: trailerVolume,
          onTrailerStop: onTrailerStop,
          sections: [
            for (var i = 0; i < sections.length; i++)
              SpotlightShelf(
                id: 'search:$query:${sections[i].addon.id}:${sections[i].catalog.id}:$i',
                title: sections[i].title,
                tag: sourceTag(sections[i]),
                onSeeAll: () => onSeeAll(sections[i]),
                nodes: i < rowNodes.length ? rowNodes[i] : const [],
                items: [
                  for (final item in sections[i].items)
                    SpotlightCard(
                      metadata: item,
                      title: item.name,
                      rating: item.imdbRating,
                      image: landscape
                          ? homeStageWideArtwork(item)
                          : item.poster,
                      fallbackImage: landscape ? item.poster : null,
                      shape: landscape
                          ? SpotlightCardShape.wide
                          : SpotlightCardShape.poster,
                      watchedImdbId: item.progressId ?? item.id,
                      watchedContentType: item.type,
                      onOpen: () => onOpen(sections[i], item),
                      onOptions: onPlay == null
                          ? null
                          : () => onPlay(item, sections[i].addon),
                    ),
                ],
              ),
          ],
          onLoadMoreRow: (row) {
            if (row < 0 || row >= sections.length) return;
            onLoadMore(sections[row]);
          },
        ),
      ),
    ],
  );
}
