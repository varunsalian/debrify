import 'package:flutter/material.dart';
import '../../models/stremio_addon.dart';
import '../../services/trakt/trakt_service.dart';

/// Actions available in the Trakt episode overflow menu.
enum TraktEpisodeMenuAction {
  markWatched,
  markUnwatched,
  rate,
}

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
                  Icon(Icons.star_rate_rounded,
                      color: Color(0xFFFBBF24), size: 24),
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
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(rating),
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
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white54)),
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
    BuildContext context) async {
  final lists = await TraktService.instance.fetchCustomLists();
  if (!context.mounted) return null;
  if (lists.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('No custom lists found. Create one on Trakt first.'),
      backgroundColor: Color(0xFFEF4444),
    ));
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
                    Icon(Icons.playlist_add,
                        color: Color(0xFFEC4899), size: 24),
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
                        leading: const Icon(Icons.playlist_play,
                            color: Color(0xFFEC4899)),
                        title: Text(name,
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text('$itemCount items',
                            style: const TextStyle(color: Colors.white54)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        onTap: () => Navigator.of(dialogContext).pop(list),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.white54)),
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
Future<void> handleTraktMenuAction(
  BuildContext context,
  StremioMeta item,
  TraktItemMenuAction action,
) async {
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
      final rating = await showTraktRatingDialog(context);
      if (rating == null) return;
      actionLabel = 'Rated $rating/10 on Trakt';
      success = await traktService.rateItem(imdbId, type, rating);
    case TraktItemMenuAction.addToList:
      if (!context.mounted) return;
      final list = await showTraktCustomListPickerDialog(context);
      if (list == null) return;
      final listSlug = list['ids']?['slug'] as String? ??
          list['ids']?['trakt']?.toString();
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
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(success ? actionLabel : 'Failed: $actionLabel'),
    backgroundColor:
        success ? const Color(0xFF34D399) : const Color(0xFFEF4444),
    duration: const Duration(seconds: 2),
  ));
}

/// Builds the add-only Trakt overflow menu (no remove actions).
/// For use in catalog/search cards where we're not in a Trakt list context.
Widget buildTraktAddOnlyOverflowMenu({
  required bool isHighlighted,
  required GlobalKey<PopupMenuButtonState<TraktItemMenuAction>> menuKey,
  required void Function(TraktItemMenuAction) onSelected,
}) {
  return Container(
    decoration: isHighlighted
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.4),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.15),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          )
        : null,
    child: PopupMenuButton<TraktItemMenuAction>(
      key: menuKey,
      icon: Icon(
        Icons.more_vert,
        size: 20,
        color: isHighlighted
            ? Colors.white
            : Colors.white.withValues(alpha: 0.7),
      ),
      tooltip: 'More options',
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: onSelected,
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: TraktItemMenuAction.addToWatchlist,
          child: Row(children: [
            Icon(Icons.bookmark_add_outlined,
                size: 18, color: Color(0xFFFBBF24)),
            SizedBox(width: 12),
            Text('Add to Trakt Watchlist'),
          ]),
        ),
        const PopupMenuItem(
          value: TraktItemMenuAction.addToCollection,
          child: Row(children: [
            Icon(Icons.library_add_outlined,
                size: 18, color: Color(0xFF60A5FA)),
            SizedBox(width: 12),
            Text('Add to Trakt Collection'),
          ]),
        ),
        const PopupMenuItem(
          value: TraktItemMenuAction.markWatched,
          child: Row(children: [
            Icon(Icons.visibility, size: 18, color: Color(0xFF34D399)),
            SizedBox(width: 12),
            Text('Mark as Watched on Trakt'),
          ]),
        ),
        const PopupMenuItem(
          value: TraktItemMenuAction.rate,
          child: Row(children: [
            Icon(Icons.star_rate_rounded, size: 18, color: Color(0xFFFBBF24)),
            SizedBox(width: 12),
            Text('Rate on Trakt'),
          ]),
        ),
        const PopupMenuItem(
          value: TraktItemMenuAction.addToList,
          child: Row(children: [
            Icon(Icons.playlist_add, size: 18, color: Color(0xFFEC4899)),
            SizedBox(width: 12),
            Text('Add to Trakt List...'),
          ]),
        ),
      ],
    ),
  );
}
