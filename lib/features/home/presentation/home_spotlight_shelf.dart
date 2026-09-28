import 'package:flutter/widgets.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/home_collection_rows.dart';
import '../../../utils/continue_watching_presentation.dart';
import '../../../widgets/home/spotlight_board.dart';
import '../application/home_stage_metadata.dart';
import '../models/home_favorite_row_ref.dart';
import 'home_stage_rows.dart';

/// Projects a Home rail into Spotlight's shelf/card presentation. Existing
/// actions and nodes are borrowed; stable rail identity survives front inserts.
SpotlightShelf buildHomeSpotlightShelf(
  HomeRail rail, {
  required String railKey,
  required bool landscape,
  required bool hideCollectionNames,
  required List<CatalogSection> sections,
  required List<List<FocusNode>> rowNodes,
  required String? Function(CatalogSection) catalogTag,
  required void Function(CatalogSection) onSeeAll,
  required void Function(HomeCollectionSection, StremioMeta) onCollectionOpen,
  required void Function(HomeContinuationRow, StremioMeta, int, int)
  onContinuationOptions,
  required SpotlightShelf Function(HomeFavoriteRowRef, {String? id})
  favoriteShelf,
  required SpotlightCard Function(StremioMeta, StremioAddon) catalogCard,
}) {
  // Rail identity — the same key Canvas/Atrium key their rails by — so the
  // board reuses shelf subtrees when tracker rows front-insert.
  final row = rail.cw;
  if (row != null) {
    return SpotlightShelf(
      id: railKey,
      title: row.title,
      // The tag used to be folded into the title text; now it IS the tag —
      // the same pill grammar the catalog rows wear.
      tag: row.tag,
      nodes: row.nodes,
      // Already nullable on the row itself — a tracker row with no grid
      // behind it hands over null and simply draws no chevron.
      onSeeAll: row.onSeeAll,
      // Caption-free like catalog rows in PORTRAIT off TV. LANDSCAPE flips
      // the premise: a textless still needs the title, and CW's second line
      // adds its useful episode / remaining-time context.
      captions: landscape,
      items: [
        for (var col = 0; col < row.items.length; col++)
          _continuationCard(
            row,
            row.items[col],
            rail.cwIndex,
            col,
            landscape: landscape,
            onOptions: onContinuationOptions,
          ),
      ],
    );
  }
  final fav = rail.favKind;
  if (fav != null) return favoriteShelf(fav, id: railKey);
  final i = rail.sectionIndex!;
  final section = sections[i];
  if (section is HomeCollectionSection) {
    return SpotlightShelf(
      id: railKey,
      title: section.title,
      tag: hideCollectionNames ? null : catalogTag(section),
      showHeader: !hideCollectionNames,
      nodes: i < rowNodes.length ? rowNodes[i] : const [],
      onSeeAll: () => onSeeAll(section),
      // A brand-logo tile needs no caption; captions stay on only while
      // some folder still wants its title drawn.
      captions: section.collection.folders.any((f) => !f.hideTitle),
      items: [
        for (final m in section.items)
          SpotlightCard(
            image: m.poster,
            fallbackImage: m.background,
            coverEmoji: section.folderOf(m)?.coverEmoji,
            focusGlowEnabled: section.collection.focusGlowEnabled,
            previewOnKeyboardFocus: true,
            collectionGifUrl: section.focusArtOf(m),
            collectionVideoUrl: section.focusVideoOf(m),
            title: m.name,
            shape: section.tileAspectOf(m) == 1
                ? SpotlightCardShape.square
                : section.tileAspectOf(m) > 1
                ? SpotlightCardShape.wide
                : SpotlightCardShape.poster,
            showCaption: !(section.folderOf(m)?.hideTitle ?? false),
            onOpen: () => onCollectionOpen(section, m),
          ),
      ],
    );
  }
  return SpotlightShelf(
    id: railKey,
    title: sections[i].title,
    tag: catalogTag(sections[i]),
    nodes: i < rowNodes.length ? rowNodes[i] : const [],
    // The same destination the classic rails' "See All" link opens —
    // including the tracker-list rows, which onSeeAll routes to
    // their own browser rather than the catalog pager.
    onSeeAll: () => onSeeAll(section),
    // Catalog cards go caption-free off TV in PORTRAIT — the art is the
    // label; a caption repeating the poster's own title was the
    // reference's one piece of noise we added ourselves. That rationale
    // inverts for LANDSCAPE, where the backdrop is a textless still and
    // the caption is the only identity the card has.
    captions: landscape,
    items: [for (final m in sections[i].items) catalogCard(m, section.addon)],
  );
}

SpotlightCard _continuationCard(
  HomeContinuationRow row,
  StremioMeta item,
  int cwIndex,
  int col, {
  required bool landscape,
  required void Function(HomeContinuationRow, StremioMeta, int, int) onOptions,
}) {
  final wideArt = homeStageWideArtwork(item);
  final episodeArt = item.type == 'series' ? row.episodeArtworkOf(item) : null;
  return SpotlightCard(
    metadata: item,
    episodeArtwork: landscape && episodeArt != null,
    image: landscape ? (episodeArt ?? wideArt) : item.poster,
    // An episode still is best-effort. If it fails at image-decode time (not
    // only during lookup), fall back to the same show art CW used before.
    fallbackImage: landscape
        ? (episodeArt != null ? wideArt : item.poster)
        : null,
    title: item.name,
    subtitle: continueWatchingCardSubtitle(
      episodeLabel: row.episodeOf(item),
      minutesLeft: row.remainingMinutesOf(item),
    ),
    rating: item.imdbRating,
    shape: landscape ? SpotlightCardShape.wide : SpotlightCardShape.poster,
    // `HomeContinuationRow` publishes a 0..1 fraction; the card draws 0..100.
    progress: (row.progressOf(item) ?? 0) * 100,
    onOpen: () => row.onOpen(item),
    // Spotlight used to bypass the shared CW hold handler and Quick Play
    // unconditionally. Route through the same preference-aware menu path as
    // every other Home layout so disabled means Play/Remove and enabled
    // means immediate playback on both touch and DPAD.
    onOptions: () => onOptions(row, item, cwIndex, col),
  );
}
