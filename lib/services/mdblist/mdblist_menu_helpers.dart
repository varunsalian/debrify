import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../watched_status_service.dart';
import 'mdblist_models.dart';
import 'mdblist_service.dart';

enum MdblistItemMenuAction {
  addToWatchlist,
  removeFromWatchlist,
  addToCollection,
  removeFromCollection,
  markWatched,
  markUnwatched,
  rate,
  removeRating,
  drop,
  restore,
  removeFromContinueWatching,
}

enum MdblistEpisodeMenuAction { markWatched, markUnwatched, rate, removeRating }

class MdblistMenuOption {
  const MdblistMenuOption({
    required this.action,
    required this.icon,
    required this.color,
    required this.label,
    required this.caption,
  });
  final MdblistItemMenuAction action;
  final IconData icon;
  final Color color;
  final String label;
  final String caption;
}

List<MdblistMenuOption> buildMdblistMenuOptions({
  required bool authenticated,
  required bool isSeries,
  bool inContinueWatching = false,
  MdblistTitleStatus? status,
}) {
  if (!authenticated) return const [];
  return [
    MdblistMenuOption(
      action: status?.inWatchlist == true
          ? MdblistItemMenuAction.removeFromWatchlist
          : MdblistItemMenuAction.addToWatchlist,
      icon: status?.inWatchlist == true
          ? Icons.bookmark_remove_rounded
          : Icons.bookmark_add_rounded,
      color: const Color(0xFF60A5FA),
      label: status?.inWatchlist == true
          ? 'Remove from MDBList Watchlist'
          : 'Add to MDBList Watchlist',
      caption: status?.inWatchlist == true ? 'Unwatchlist' : 'Watchlist',
    ),
    MdblistMenuOption(
      action: status?.watched == true || status?.completed == true
          ? MdblistItemMenuAction.markUnwatched
          : MdblistItemMenuAction.markWatched,
      icon: status?.watched == true || status?.completed == true
          ? Icons.remove_done_rounded
          : Icons.done_all_rounded,
      color: const Color(0xFF34D399),
      label: status?.watched == true || status?.completed == true
          ? 'Mark unwatched on MDBList'
          : 'Mark watched on MDBList',
      caption: status?.watched == true || status?.completed == true
          ? 'Unwatched'
          : 'Watched',
    ),
    MdblistMenuOption(
      action: status?.rating != null
          ? MdblistItemMenuAction.removeRating
          : MdblistItemMenuAction.rate,
      icon: status?.rating != null
          ? Icons.star_outline_rounded
          : Icons.star_rounded,
      color: const Color(0xFFFBBF24),
      label: status?.rating != null
          ? 'Remove MDBList rating'
          : 'Rate on MDBList',
      caption: status?.rating != null ? 'Unrate' : 'Rate',
    ),
    MdblistMenuOption(
      action: status?.collected == true
          ? MdblistItemMenuAction.removeFromCollection
          : MdblistItemMenuAction.addToCollection,
      icon: status?.collected == true
          ? Icons.inventory_2_outlined
          : Icons.inventory_2_rounded,
      color: const Color(0xFFA78BFA),
      label: status?.collected == true
          ? 'Remove from MDBList Collection'
          : isSeries
          ? 'Collect all aired episodes on MDBList'
          : 'Add to MDBList Collection',
      caption: status?.collected == true ? 'Uncollect' : 'Collect',
    ),
    if (isSeries && status?.dropped != null)
      MdblistMenuOption(
        action: status?.dropped == true
            ? MdblistItemMenuAction.restore
            : MdblistItemMenuAction.drop,
        icon: status?.dropped == true
            ? Icons.restore_rounded
            : Icons.cancel_outlined,
        color: const Color(0xFFF87171),
        label: status?.dropped == true
            ? 'Restore show on MDBList'
            : 'Drop show on MDBList',
        caption: status?.dropped == true ? 'Restore' : 'Drop',
      ),
    if (inContinueWatching)
      const MdblistMenuOption(
        action: MdblistItemMenuAction.removeFromContinueWatching,
        icon: Icons.remove_circle_outline_rounded,
        color: Color(0xFFF87171),
        label: 'Remove from MDBList Continue Watching',
        caption: 'Remove',
      ),
  ];
}

Future<int?> showMdblistRatingDialog(BuildContext context) => showDialog<int>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: const Text('Rate on MDBList'),
    content: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var rating = 1; rating <= 10; rating++)
          SizedBox.square(
            dimension: 48,
            child: FilledButton.tonal(
              onPressed: () => Navigator.pop(dialogContext, rating),
              child: Text('$rating'),
            ),
          ),
      ],
    ),
  ),
);

Future<void> handleMdblistMenuAction(
  BuildContext context,
  StremioMeta item,
  MdblistItemMenuAction action, {
  int? presetRating,
}) async {
  final imdb = item.effectiveImdbId ?? item.id;
  if (!imdb.startsWith('tt')) return;
  final ids = MdblistMediaIds(imdb: imdb);
  final type = item.type == 'series' ? 'show' : 'movie';
  final service = MdblistService.instance;
  bool success;
  String label;
  switch (action) {
    case MdblistItemMenuAction.addToWatchlist:
      success = await service.addToWatchlist(ids, type);
      label = 'Added to MDBList Watchlist';
    case MdblistItemMenuAction.removeFromWatchlist:
      success = await service.removeFromWatchlist(ids, type);
      label = 'Removed from MDBList Watchlist';
    case MdblistItemMenuAction.markWatched:
      success = await service.markWatched(ids, type);
      label = 'Marked watched on MDBList';
    case MdblistItemMenuAction.markUnwatched:
      success = await service.markUnwatched(ids, type);
      label = 'Marked unwatched on MDBList';
    case MdblistItemMenuAction.rate:
      if (!context.mounted) return;
      final rating = presetRating ?? await showMdblistRatingDialog(context);
      if (rating == null) return;
      success = await service.rateTitle(ids, type, rating);
      label = 'Rated $rating/10 on MDBList';
    case MdblistItemMenuAction.removeRating:
      success = await service.removeRating(ids, type);
      label = 'Removed MDBList rating';
    case MdblistItemMenuAction.addToCollection:
      if (item.type == 'series') {
        if (!context.mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Collect this show?'),
            content: const Text(
              'MDBList will add every aired episode to your collection.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Collect'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
      success = await service.addToCollection(ids, type);
      label = 'Added to MDBList Collection';
    case MdblistItemMenuAction.removeFromCollection:
      success = await service.removeFromCollection(ids, type);
      label = 'Removed from MDBList Collection';
    case MdblistItemMenuAction.drop:
      success = await service.setDropped(ids, dropped: true);
      label = 'Dropped on MDBList';
    case MdblistItemMenuAction.restore:
      success = await service.setDropped(ids, dropped: false);
      label = 'Restored on MDBList';
    case MdblistItemMenuAction.removeFromContinueWatching:
      // The generic menu helper does not carry a paused episode's season and
      // episode coordinates. Surfaces that expose this context-only action
      // intercept it and route through MdblistContinueWatchingService.clear.
      return;
  }
  if (success &&
      (action == MdblistItemMenuAction.markWatched ||
          action == MdblistItemMenuAction.markUnwatched)) {
    // This action is already on an active UI surface, so consume the dirty
    // watched-state marker now. Playback scrobbles remain deferred until Home
    // is revealed.
    WatchedStatusService.instance.ensureStarted();
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(success ? label : 'Failed: $label'),
      backgroundColor: success
          ? const Color(0xFF34D399)
          : const Color(0xFFEF4444),
    ),
  );
}
