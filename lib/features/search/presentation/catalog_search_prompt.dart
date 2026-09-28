import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../utils/tv_keys.dart';

/// Empty state for the dedicated Search tab before the user types.
Widget buildCatalogSearchPrompt(
  BuildContext context, {
  required Widget Function() sourcesButton,
}) {
  final app = AppThemeScope.of(context);
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_rounded,
            size: 54,
            color: app.fade(app.core.tx, 0.22),
          ),
          const SizedBox(height: 16),
          Text(
            'Search movies & shows',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: app.fade(app.core.tx, 0.8),
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          // Only reached in Catalog mode — _buildBody routes Keyword mode to
          // _buildKeyword (which has its own empty state) before it gets here.
          Text(
            'Type a title to search your catalogs, or switch to Keyword to '
            'search torrents directly.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: app.fade(app.core.tx, 0.5),
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          // Pick which searchable addons the catalog search queries. Mirrors
          // the keyword tab's Sources button; DPAD reaches it via the search
          // field's Down handler.
          sourcesButton(),
        ],
      ),
    ),
  );
}

/// "Sources" button for catalog search — opens a dialog to enable/disable
/// the search-capable addons, persisted across launches. Catalog-mode twin
/// of the Keyword Sources control.
Widget buildCatalogSourcesButton(
  BuildContext context, {
  required FocusNode focusNode,
  required VoidCallback onOpen,
  required VoidCallback onUp,
  required VoidCallback onSidebar,
}) {
  final app = AppThemeScope.of(context);
  final scheme = Theme.of(context).colorScheme;
  return Focus(
    focusNode: focusNode,
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
        onOpen();
        return KeyEventResult.handled;
      }
      // Up returns to the search field, Left hands off to the sidebar.
      if (key == LogicalKeyboardKey.arrowUp) {
        onUp();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        onSidebar();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpen,
            borderRadius: app.shape.brPill,
            canRequestFocus: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: app.shape.brPill,
                border: Border.all(
                  color: focused
                      ? app.fade(app.core.tx, 0.9)
                      : app.fade(app.core.tx, 0.10),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.dns_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Sources',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
