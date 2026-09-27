import 'package:flutter/widgets.dart';
import '../../../models/stremio_addon.dart';
import '../models/home_favorite_row_ref.dart';

// These are presentation descriptors, not application state. Collections and
// focus nodes are borrowed from the composing view and must not be mutated or
// disposed by a layout. Keeping their live references preserves focus and lazy
// callbacks when rows change while an existing view or menu is still mounted.

enum HomeContinuationKind { local, trakt, simkl, mdblist, iptv }

/// A leading "Continue Watching" board row (local or Trakt). Carries its own
/// header, focus nodes, per-item progress lookup, and open / quick-play
/// handlers so the local and Trakt sources render through one row builder.
class HomeContinuationRow {
  final String rowId;
  final String title; // e.g. 'Continue Watching' or 'Trakt Movies'
  final String? tag; // 'Movies' / 'Series' pill, or null
  final HomeContinuationKind kind;
  final List<StremioMeta> items;
  final List<FocusNode> nodes;
  final double? Function(StremioMeta) progressOf;

  /// Subtle 'S2 · E5' label for series cards (null for movies / when unknown).
  final String? Function(StremioMeta) episodeOf;

  /// Whole minutes remaining when this provider has a trustworthy duration.
  final int? Function(StremioMeta) remainingMinutesOf;

  /// Episode still for landscape series cards, resolved asynchronously and
  /// null until available. The card keeps its show-art fallback throughout.
  final String? Function(StremioMeta) episodeArtworkOf;
  final void Function(StremioMeta) onOpen;
  final void Function(StremioMeta) onQuickPlay;

  /// Takes the title off THIS row's source and reloads it. Long-press (hold-OK
  /// on TV) offers it next to Play through the caller-owned card menu.
  final Future<void> Function(StremioMeta) onRemove;
  final bool Function(StremioMeta)? canRemove;

  /// Opens the "See All" grid for this row's source, or null to hide the link.
  final VoidCallback? onSeeAll;

  const HomeContinuationRow({
    required this.rowId,
    required this.title,
    required this.tag,
    required this.kind,
    required this.items,
    required this.nodes,
    required this.progressOf,
    required this.episodeOf,
    required this.remainingMinutesOf,
    required this.episodeArtworkOf,
    required this.onOpen,
    required this.onQuickPlay,
    required this.onRemove,
    this.canRemove,
    this.onSeeAll,
  });
}

/// One Canvas rail — a Continue Watching row ([cw] non-null, with its
/// position among the CW rows in [cwIndex]), a favourites-family rail
/// ([favKind] non-null: IPTV / Debrify TV / Stremio TV / Playlist / an IPTV
/// custom-list row), or a catalog section ([sectionIndex] into
/// the caller-owned catalog sections and focus rows).
class HomeRail {
  final HomeContinuationRow? cw;
  final int cwIndex;
  final HomeFavoriteRowRef? favKind;
  final int? sectionIndex;
  final int traktSkeletonIndex;
  const HomeRail({
    this.cw,
    this.cwIndex = -1,
    this.favKind,
    this.sectionIndex,
    this.traktSkeletonIndex = -1,
  });
}

/// What a stage board resolved for this frame — the rail list, which one is
/// active, its identity key, its items and its focus nodes.
class HomeStageRailView {
  final List<HomeRail> rails;
  final int index;
  final HomeRail rail;
  final String key;
  final List<StremioMeta> items;
  final List<FocusNode> nodes;
  const HomeStageRailView({
    required this.rails,
    required this.index,
    required this.rail,
    required this.key,
    required this.items,
    required this.nodes,
  });
}

/// One row of Tonight's Continue Watching queue: which CW rail it came from
/// and which column within it (so the cell's FocusNode, progress, episode
/// label and open/remove actions all come from the row's own contract).
class HomeTonightQueueEntry {
  final HomeRail rail;
  final int col;
  const HomeTonightQueueEntry({required this.rail, required this.col});
}
