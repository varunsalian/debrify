import 'package:flutter/material.dart';
import '../../../widgets/skeleton_poster.dart' show BrandLoadingStage;

/// Shared board states and layout dispatch. Builders stay lazy so hidden
/// layouts do not create resources or evaluate their route-dependent content.
Widget buildHomeBoardContent({
  required bool loading,
  required bool isTelevision,
  required String? error,
  required bool continuationVisible,
  required bool catalogsEmpty,
  required bool favoritesVisible,
  required bool traktReserving,
  required String query,
  required int searchFailures,
  required bool searchMode,
  required String style,
  required bool Function() spotlightHasContent,
  required Map<String, Widget Function()> layouts,
  required Widget Function() searchSpotlight,
  required Widget Function() classic,
  required VoidCallback onRetry,
  required Widget Function(IconData, String, String, {VoidCallback? onRetry})
  message,
}) {
  if (loading) {
    // The brand moment: DEBRIFY centred on the ink while catalogs load —
    // replaces the old skeleton-rail wall, which read as a broken app.
    return BrandLoadingStage(isTelevision: isTelevision);
  }
  if (error != null) {
    return message(
      Icons.error_outline_rounded,
      "Couldn't load catalogs",
      error,
      onRetry: onRetry,
    );
  }
  final showCw = continuationVisible;
  // Don't fall through to the empty-state message while Trakt rows are being
  // reserved — the skeletons below are the board's content until the fetch
  // settles, and showing "No catalogs yet" first would flip to rows with the
  // exact reflow the reservation exists to prevent.
  if (catalogsEmpty && !showCw && !favoritesVisible && !traktReserving) {
    if (query.isNotEmpty) {
      return message(
        Icons.search_off_rounded,
        'No catalog matches',
        searchFailures > 0
            ? 'Nothing in your catalogs for "$query" — and '
                  '$searchFailures source'
                  '${searchFailures == 1 ? '' : 's'} didn\'t '
                  'respond, so there may be more. Try again, or switch to '
                  'Keyword to search torrents directly.'
            : 'Nothing in your catalogs for "$query". Try different '
                  'keywords, or switch to Keyword to search torrents '
                  'directly.',
      );
    }
    return message(
      Icons.travel_explore_rounded,
      'No catalogs yet',
      'Install a catalog add-on (e.g. Cinemeta) from Addons to browse '
          'movies and shows here.',
    );
  }

  if (isTelevision && searchMode) {
    return searchSpotlight();
  }

  final layout = layouts[style];
  if (layout != null && (style != 'spotlight' || spotlightHasContent())) {
    return layout();
  }
  return classic();
}
