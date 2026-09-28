import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';
import '../../home/presentation/home_spotlight_search_button.dart';
import '../models/search_mode.dart';

/// Route chrome shared by Home, Discover and the dedicated Search surface.
/// Builders retain branch laziness and use the host's original build context.
Widget buildSearchPageShell({
  required BuildContext context,
  required bool glassHome,
  required bool discoverMode,
  required bool isTelevision,
  required bool dedicatedSearch,
  required bool Function() spotlightActive,
  required Widget Function() discover,
  required Widget Function() board,
  required Widget Function() spotlight,
  required Widget Function() header,
  required Widget Function() sourcesBar,
  required Widget Function() body,
}) {
  // The TV Home board is TRANSPARENT down to the app shell: the glass stage
  // (TvAmbientArtStage, painted BEHIND the sidebar rail in main.dart) is the
  // real background, so the focused title's blurred art fills the whole
  // screen — rail strip included. Every other mode keeps the opaque indigo
  // bloom below.
  final app = AppThemeScope.of(context);
  return Scaffold(
    backgroundColor: glassHome ? Colors.transparent : app.home.bg,
    // A restrained indigo bloom near the top fading fast into near-black —
    // toned down from a saturated purple so the posters carry the colour
    // (Stremio's home grid is nearly monochrome).
    body: Container(
      decoration: glassHome ? null : BoxDecoration(gradient: app.home.wash),
      // Four layouts:
      //  • Dedicated Search tab (searchMode) — the field + Catalog/Keyword
      //    toggle over a blank prompt until the user types (TV only).
      //  • Home-New board on TV — chrome-free hero + rows, no search bar
      //    (search lives in its own tab).
      //  • Off-TV Home with Spotlight selected — the full-bleed shell with
      //    search behind a button (see spotlight). The hero owns
      //    the status-bar region, so SafeArea's top inset is the shell's to
      //    manage.
      //  • Home-New board on desktop/mobile classic — keeps a persistent
      //    search bar above the board; the separate Search tab is an
      //    additional way in on TV and sidebar layouts, not a replacement.
      child: discoverMode
          ? SafeArea(child: discover())
          : (isTelevision && !dedicatedSearch)
          ? SafeArea(child: board())
          : spotlightActive()
          ? spotlight()
          : SafeArea(
              child: Column(
                children: [
                  header(),
                  sourcesBar(),
                  Expanded(child: body()),
                ],
              ),
            ),
    ),
  );
}

/// Spotlight keeps the hero full-bleed until its existing search sheet opens.
Widget buildSpotlightSearchShell({
  required BuildContext context,
  required bool sheetOpen,
  required bool canClose,
  required VoidCallback onOpen,
  required VoidCallback onClose,
  required Widget Function() header,
  required Widget Function() sourcesBar,
  required Widget Function() body,
}) {
  if (sheetOpen) {
    return SafeArea(
      child: Column(
        children: [
          // Close affordance: only on the blank catalog prompt — with any
          // query or keyword state active, Back (hardware or gesture) is
          // the way out, and it resets atomically via onClose.
          if (canClose)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 4),
                child: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Hide search',
                  onPressed: onClose,
                ),
              ),
            ),
          header(),
          sourcesBar(),
          Expanded(child: body()),
        ],
      ),
    );
  }
  final topInset = MediaQuery.viewPaddingOf(context).top;
  return SafeArea(
    top: false,
    child: Stack(
      children: [
        Positioned.fill(child: body()),
        Positioned(
          top: topInset + 10,
          right: HomeSpotlightSearchButton.rightInset,
          child: HomeSpotlightSearchButton(onTap: onOpen),
        ),
      ],
    ),
  );
}

/// Animated Sources affordance beneath the unified, non-TV search field.
Widget buildUnifiedCatalogSourcesBar({
  required bool isTelevision,
  required bool dedicatedSearch,
  required bool show,
  required Widget Function() sourcesButton,
}) {
  if (isTelevision || dedicatedSearch) {
    return const SizedBox.shrink();
  }
  return AnimatedSize(
    duration: const Duration(milliseconds: 160),
    curve: Curves.easeOut,
    alignment: Alignment.topCenter,
    child: !show
        ? const SizedBox(width: double.infinity)
        : Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: sourcesButton(),
                ),
              ),
            ),
          ),
  );
}

/// Search mode routing, including streamed catalog loading and the blank prompt.
Widget buildSearchModeContent({
  required SearchMode mode,
  required bool catalogSearching,
  required bool catalogEmpty,
  required bool dedicatedSearch,
  required bool queryEmpty,
  required Widget Function() keyword,
  required Widget Function() lists,
  required Widget Function() prompt,
  required Widget Function() board,
}) {
  if (mode == SearchMode.keyword) return keyword();
  if (mode == SearchMode.lists) return lists();
  // Full-screen spinner only until the FIRST result row streams in — after
  // that the board renders and late rows append beneath it (a slim progress
  // strip in board signals the search is still running).
  if (catalogSearching && catalogEmpty) {
    return const Center(child: CircularProgressIndicator());
  }
  // Dedicated Search tab: blank prompt until there's a query (no hero/board).
  if (dedicatedSearch && queryEmpty) {
    return prompt();
  }
  return board();
}
