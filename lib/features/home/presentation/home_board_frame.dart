import 'package:flutter/material.dart';
import 'home_catalog_continuation_footer.dart';

/// Frames the board and continuation controls without mounting hidden content.
/// Focus nodes and paging work belong to the caller.
Widget buildHomeBoardFrame({
  required bool loading,
  required bool hasError,
  required bool hasCatalogs,
  required bool catalogsEmpty,
  required bool continuationVisible,
  required bool favoritesVisible,
  required bool hasPausedRows,
  required bool hasMoreCatalogs,
  required bool busy,
  required FocusNode continueNode,
  required FocusNode moreNode,
  required VoidCallback onRestoreFocus,
  required VoidCallback onContinueRows,
  required VoidCallback onMoreCatalogs,
  required Widget Function() content,
  required Widget Function(IconData, String, String) message,
}) {
  final showContinuation = hasPausedRows || (hasMoreCatalogs && catalogsEmpty);
  return Column(
    children: [
      Expanded(
        child:
            !loading &&
                !hasError &&
                hasCatalogs &&
                catalogsEmpty &&
                !continuationVisible &&
                !favoritesVisible
            ? message(
                Icons.movie_filter_rounded,
                !showContinuation
                    ? 'No unwatched titles found'
                    : 'No new titles loaded yet',
                !showContinuation
                    ? 'Try another catalog or turn off Hide watched titles in Tracking settings.'
                    : 'Continue browsing to check more titles in these catalogs.',
              )
            : content(),
      ),
      if (!loading && showContinuation)
        buildHomeCatalogContinuationFooter(
          hasPausedRows: hasPausedRows,
          hasMoreCatalogs: hasMoreCatalogs,
          catalogsEmpty: catalogsEmpty,
          busy: busy,
          continueNode: continueNode,
          moreNode: moreNode,
          onRestoreFocus: onRestoreFocus,
          onContinueRows: onContinueRows,
          onMoreCatalogs: onMoreCatalogs,
        ),
    ],
  );
}
