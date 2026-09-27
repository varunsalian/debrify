import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/home/catalog_continuation_button.dart';

/// Paging actions below the board. Nodes and asynchronous work belong to the
/// caller; busy actions stay focusable and Up returns to the caller's board.
/// The caller decides whether the footer is present while loading or exhausted.
Widget buildHomeCatalogContinuationFooter({
  required bool hasPausedRows,
  required bool hasMoreCatalogs,
  required bool catalogsEmpty,
  required bool busy,
  required FocusNode continueNode,
  required FocusNode moreNode,
  required VoidCallback onRestoreFocus,
  required VoidCallback onContinueRows,
  required VoidCallback onMoreCatalogs,
}) => SafeArea(
  top: false,
  child: Focus(
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowUp) {
        onRestoreFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Wrap(
      alignment: WrapAlignment.center,
      children: [
        if (hasPausedRows)
          CatalogContinuationButton(
            focusNode: continueNode,
            autofocus: catalogsEmpty,
            busy: busy,
            label: 'Continue paused rows',
            onPressed: onContinueRows,
          ),
        if (hasMoreCatalogs)
          CatalogContinuationButton(
            focusNode: moreNode,
            autofocus: !hasPausedRows && catalogsEmpty,
            busy: busy,
            label: 'Load more catalogs',
            onPressed: onMoreCatalogs,
          ),
      ],
    ),
  ),
);
