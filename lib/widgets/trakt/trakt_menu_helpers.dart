import 'package:flutter/material.dart';
import '../../models/stremio_addon.dart';
import '../../services/trakt/trakt_service.dart';

/// Actions available in the Trakt episode overflow menu.
enum TraktEpisodeMenuAction { markWatched, markUnwatched, rate }

/// Actions available in the Trakt item overflow menu.
enum TraktItemMenuAction {
  addToWatchlist,
  removeFromWatchlist,
  addToCollection,
  removeFromCollection,
  markWatched,
  markUnwatched,
  rate,
  removeRating,
  addToList,
  removeFromList,
  removeFromPlayback,
  removeFromTraktPlayback,
  addToStremioTv,
  selectSource,
  playRandomEpisode,
  searchPacks,
}

/// Shows a 1-10 rating dialog. Returns the selected rating or null.
Future<int?> showTraktRatingDialog(BuildContext context) {
  return showDialog<int>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.star_rate_rounded,
                    color: Color(0xFFFBBF24),
                    size: 24,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Rate this item',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: List.generate(10, (i) {
                  final rating = i + 1;
                  return SizedBox(
                    width: 52,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF334155),
                        foregroundColor: const Color(0xFFFBBF24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(rating),
                      child: Text(
                        '$rating',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Shows a custom list picker dialog. Returns the selected list or null.
Future<Map<String, dynamic>?> showTraktCustomListPickerDialog(
  BuildContext context,
) async {
  final lists = await TraktService.instance.fetchCustomLists();
  if (!context.mounted) return null;
  if (lists.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No custom lists found. Create one on Trakt first.'),
        backgroundColor: Color(0xFFEF4444),
      ),
    );
    return null;
  }

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.playlist_add,
                      color: Color(0xFFEC4899),
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Add to List',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: lists.length,
                    itemBuilder: (context, index) {
                      final list = lists[index];
                      final name = list['name'] as String? ?? 'Unknown';
                      final itemCount = list['item_count'] as int? ?? 0;
                      return ListTile(
                        leading: const Icon(
                          Icons.playlist_play,
                          color: Color(0xFFEC4899),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          '$itemCount items',
                          style: const TextStyle(color: Colors.white54),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onTap: () => Navigator.of(dialogContext).pop(list),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Handles a Trakt menu action for a given item. Shows snackbar feedback.
/// Standalone handler for use outside of TraktResultsView (catalog/search cards).
/// [onSelectSource] is called when user selects the "Select Source" action for a series.
Future<void> handleTraktMenuAction(
  BuildContext context,
  StremioMeta item,
  TraktItemMenuAction action, {
  void Function(StremioMeta)? onSelectSource,
  void Function(StremioMeta)? onEditSource,
  Future<void> Function(StremioMeta)? onPlayRandomEpisode,
  void Function(StremioMeta)? onSearchPacks,
  Future<void> Function(StremioMeta)? onAddToStremioTv,
  /// Skips the rating dialog for [TraktItemMenuAction.rate] and submits this
  /// value directly — for surfaces that pick the rating themselves (the merged
  /// detail sheet's inline 1–10 strip). Omit it and the dialog behaves as
  /// before.
  int? presetRating,
}) async {
  final traktService = TraktService.instance;
  final imdbId = item.effectiveImdbId ?? item.id;
  final type = item.type;
  bool success = false;
  String actionLabel = '';

  switch (action) {
    case TraktItemMenuAction.addToWatchlist:
      actionLabel = 'Added to Trakt Watchlist';
      success = await traktService.addToWatchlist(imdbId, type);
    case TraktItemMenuAction.addToCollection:
      actionLabel = 'Added to Trakt Collection';
      success = await traktService.addToCollection(imdbId, type);
    case TraktItemMenuAction.markWatched:
      actionLabel = 'Marked as Watched on Trakt';
      success = await traktService.addToHistory(imdbId, type);
    case TraktItemMenuAction.rate:
      if (!context.mounted) return;
      final rating = presetRating ?? await showTraktRatingDialog(context);
      if (rating == null) return;
      actionLabel = 'Rated $rating/10 on Trakt';
      success = await traktService.rateItem(imdbId, type, rating);
    case TraktItemMenuAction.addToList:
      if (!context.mounted) return;
      final list = await showTraktCustomListPickerDialog(context);
      if (list == null) return;
      final listSlug =
          list['ids']?['slug'] as String? ?? list['ids']?['trakt']?.toString();
      if (listSlug == null || listSlug.isEmpty) return;
      actionLabel = 'Added to Trakt list "${list['name']}"';
      success = await traktService.addToCustomList(listSlug, imdbId, type);
    // Remove actions — not used by add-only menu but handled for completeness
    case TraktItemMenuAction.removeFromWatchlist:
      actionLabel = 'Removed from Watchlist';
      success = await traktService.removeFromWatchlist(imdbId, type);
    case TraktItemMenuAction.removeFromCollection:
      actionLabel = 'Removed from Collection';
      success = await traktService.removeFromCollection(imdbId, type);
    case TraktItemMenuAction.markUnwatched:
      actionLabel = 'Marked as Unwatched';
      success = await traktService.removeFromHistory(imdbId, type);
    case TraktItemMenuAction.removeRating:
      actionLabel = 'Rating Removed';
      success = await traktService.removeRating(imdbId, type);
    case TraktItemMenuAction.removeFromList:
      return; // No context for which list to remove from
    case TraktItemMenuAction.removeFromPlayback:
      return; // Only handled in TraktResultsView which has playback IDs
    case TraktItemMenuAction.removeFromTraktPlayback:
      return; // Handled by callers that hold the TraktContinueWatchingItem
    case TraktItemMenuAction.addToStremioTv:
      await onAddToStremioTv?.call(item);
      return;
    case TraktItemMenuAction.selectSource:
      if (onEditSource != null) {
        // Caller handles edit-vs-select logic
        onEditSource.call(item);
      } else {
        onSelectSource?.call(item);
      }
      return;
    case TraktItemMenuAction.playRandomEpisode:
      await onPlayRandomEpisode?.call(item);
      return;
    case TraktItemMenuAction.searchPacks:
      onSearchPacks?.call(item);
      return;
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(success ? actionLabel : 'Failed: $actionLabel'),
      backgroundColor: success
          ? const Color(0xFF34D399)
          : const Color(0xFFEF4444),
      duration: const Duration(seconds: 2),
    ),
  );
}

// ── Quick actions ───────────────────────────────────────────────────────────

/// One Trakt action in the inline quick-action row. [caption] is the short
/// label shown under the icon; [label] is the full descriptive form.
class TraktMenuOption {
  final TraktItemMenuAction action;
  final IconData icon;
  final Color color;
  final String label;
  final String caption;

  /// True for actions that sync to Trakt — the row shows a TRAKT badge.
  final bool isTrakt;

  const TraktMenuOption({
    required this.action,
    required this.icon,
    required this.color,
    required this.label,
    required this.caption,
    this.isTrakt = false,
  });
}

/// Structured (icon/color/label) Trakt actions for the inline quick-action
/// strip on the catalog detail screen.
List<TraktMenuOption> buildTraktAddOnlyMenuOptions({
  bool isSeries = false,
  bool isMovie = false,
  bool hasBoundSource = false,
  bool isTraktAuthenticated = true,
  // null = watched state unknown (offer both mark-watched and mark-unwatched);
  // true = show only "Unwatched"; false = show only "Watched".
  bool? isWatched,
  // The user's live Trakt relationship to this title. When provided, the
  // watchlist/collection/rating entries become state-aware toggles (Add ↔
  // Remove) instead of blind "Add" actions, and its `watched` overrides
  // [isWatched] for movies. Null → the legacy add-only behaviour.
  TraktTitleStatus? status,
}) {
  // Effective watched state: a movie's authoritative Trakt watched flag wins;
  // otherwise fall back to the caller's hint (series stay null → offer both).
  final bool? effectiveWatched = status?.watched ?? isWatched;
  final bool inWatchlist = status?.inWatchlist ?? false;
  final bool inCollection = status?.inCollection ?? false;
  final int? currentRating = status?.rating;
  return [
    // App / Stremio actions first.
    if (isSeries || isMovie)
      TraktMenuOption(
        action: TraktItemMenuAction.selectSource,
        icon: hasBoundSource ? Icons.edit_rounded : Icons.link_rounded,
        color: const Color(0xFF60A5FA),
        label: hasBoundSource
            ? (isMovie ? 'Edit Source' : 'Edit Sources')
            : 'Select Source',
        caption: hasBoundSource ? 'Edit Source' : 'Select Source',
      ),
    if (isSeries || isMovie)
      const TraktMenuOption(
        action: TraktItemMenuAction.addToStremioTv,
        icon: Icons.live_tv_rounded,
        color: Color(0xFF22C55E),
        label: 'Add to Stremio TV',
        caption: 'Stremio TV',
      ),
    if (isSeries)
      const TraktMenuOption(
        action: TraktItemMenuAction.playRandomEpisode,
        icon: Icons.shuffle_rounded,
        color: Color(0xFFF59E0B),
        label: 'Play Random Episode',
        caption: 'Random',
      ),
    if (isSeries)
      const TraktMenuOption(
        action: TraktItemMenuAction.searchPacks,
        icon: Icons.inventory_2_rounded,
        color: Color(0xFFFBBF24),
        label: 'Search Season Packs',
        caption: 'Packs',
      ),
    // Trakt-syncing actions — badged TRAKT in the UI. When [status] is known
    // these flip between Add and Remove to mirror the user's real library.
    if (isTraktAuthenticated) ...[
      if (inWatchlist)
        const TraktMenuOption(
          action: TraktItemMenuAction.removeFromWatchlist,
          icon: Icons.bookmark_remove_rounded,
          color: Color(0xFFFBBF24),
          label: 'Remove from Trakt Watchlist',
          caption: 'In Watchlist',
          isTrakt: true,
        )
      else
        const TraktMenuOption(
          action: TraktItemMenuAction.addToWatchlist,
          icon: Icons.bookmark_add_rounded,
          color: Color(0xFFFBBF24),
          label: 'Add to Trakt Watchlist',
          caption: 'Watchlist',
          isTrakt: true,
        ),
      if (inCollection)
        const TraktMenuOption(
          action: TraktItemMenuAction.removeFromCollection,
          icon: Icons.video_library_rounded,
          color: Color(0xFF60A5FA),
          label: 'Remove from Trakt Collection',
          caption: 'In Collection',
          isTrakt: true,
        )
      else
        const TraktMenuOption(
          action: TraktItemMenuAction.addToCollection,
          icon: Icons.video_library_outlined,
          color: Color(0xFF60A5FA),
          label: 'Add to Trakt Collection',
          caption: 'Collection',
          isTrakt: true,
        ),
      // When the watched state is known (effectiveWatched), show the single
      // relevant toggle like the old home item menu. When it's unknown (series
      // whose whole-title completion is fuzzy) offer BOTH so an already-watched
      // title can always be un-marked instead of only re-marked.
      if (effectiveWatched != true)
        const TraktMenuOption(
          action: TraktItemMenuAction.markWatched,
          icon: Icons.check_circle_rounded,
          color: Color(0xFF34D399),
          label: 'Mark as Watched on Trakt',
          caption: 'Watched',
          isTrakt: true,
        ),
      if (effectiveWatched != false)
        const TraktMenuOption(
          action: TraktItemMenuAction.markUnwatched,
          icon: Icons.visibility_off_rounded,
          color: Color(0xFF34D399),
          label: 'Mark as Unwatched on Trakt',
          caption: 'Unwatch',
          isTrakt: true,
        ),
      // Rating: once rated, offer "Change Rating" plus a distinct "Remove
      // Rating"; otherwise a plain "Rate".
      TraktMenuOption(
        action: TraktItemMenuAction.rate,
        icon: Icons.star_rounded,
        color: const Color(0xFFFBBF24),
        label: currentRating != null
            ? 'Change Trakt Rating ($currentRating/10)'
            : 'Rate on Trakt',
        caption: currentRating != null ? 'Rated $currentRating' : 'Rate',
        isTrakt: true,
      ),
      if (currentRating != null)
        const TraktMenuOption(
          action: TraktItemMenuAction.removeRating,
          icon: Icons.star_outline_rounded,
          color: Color(0xFFFBBF24),
          label: 'Remove Trakt Rating',
          caption: 'Unrate',
          isTrakt: true,
        ),
      const TraktMenuOption(
        action: TraktItemMenuAction.addToList,
        icon: Icons.playlist_add_rounded,
        color: Color(0xFFEC4899),
        label: 'Add to Trakt List…',
        caption: 'Add to List',
        isTrakt: true,
      ),
    ],
  ];
}

