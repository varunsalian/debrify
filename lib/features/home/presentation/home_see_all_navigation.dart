import 'package:flutter/material.dart';

import '../../../models/stremio_addon.dart';
import '../../../screens/see_all/catalog_see_all_screen.dart';
import '../../../screens/see_all/continue_watching_see_all_screen.dart';
import '../../../screens/see_all/mdblist_see_all_screen.dart';
import '../../../screens/see_all/simkl_see_all_screen.dart';
import '../../../screens/see_all/trakt_see_all_screen.dart';
import '../../../services/home_list_rows.dart'
    show HomeListSection, HomeExtraRowIds;

/// Home's grid routes. Borrowed readers preserve each route's existing snapshot
/// timing; playback and refresh actions stay with their application owners.
class HomeSeeAllNavigation {
  const HomeSeeAllNavigation({
    required this.isTelevision,
    required this.pikpakOnly,
    required this.wrap,
    required this.isBound,
    required this.afterReturn,
    required this.afterTrackerReturn,
    required this.traktItems,
    required this.traktProgress,
    required this.simklItems,
    required this.simklProgress,
    required this.openTraktItem,
    required this.playTraktItem,
    required this.openSimklItem,
    required this.playSimklItem,
    required this.openSimklCwItem,
    required this.playSimklCwItem,
    required this.openMdblist,
    required this.playMdblist,
    required this.openItem,
    required this.playItem,
  });

  final bool Function() isTelevision;
  final bool Function() pikpakOnly;
  final Widget Function(Widget) wrap;
  final bool Function(StremioMeta) isBound;
  final Future<void> Function() afterReturn;
  final Future<void> Function() afterTrackerReturn;
  final List<StremioMeta> Function() traktItems;
  final Map<String, double> Function() traktProgress;
  final List<StremioMeta> Function() simklItems;
  final Map<String, double> Function() simklProgress;
  final ValueChanged<StremioMeta> openTraktItem;
  final ValueChanged<StremioMeta> playTraktItem;
  final ValueChanged<StremioMeta> openSimklItem;
  final ValueChanged<StremioMeta> playSimklItem;
  final ValueChanged<StremioMeta> openSimklCwItem;
  final ValueChanged<StremioMeta> playSimklCwItem;
  final ValueChanged<StremioMeta> openMdblist;
  final ValueChanged<StremioMeta> playMdblist;
  final void Function(StremioMeta, StremioAddon) openItem;
  final void Function(StremioMeta, StremioAddon) playItem;

  void openCatalog(BuildContext context, CatalogSection section) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => wrap(
              CatalogSeeAllScreen(
                addon: section.addon,
                initialCatalog: section.catalog,
                seedItems: List<StremioMeta>.of(section.items),
                seedNextSkip: section.nextSkip,
                // Search sections carry their query → See All keeps searching
                // this catalog (paged) instead of browsing it.
                query: section.query,
                isTelevision: isTelevision(),
                onOpenItem: (item) => openItem(item, section.addon),
                onQuickPlay: pikpakOnly()
                    ? null
                    : (item) => playItem(item, section.addon),
                // Bound-source badges are intentionally omitted here: isBound only
                // tracks rail/CW items (not See-All paged items) and wouldn't
                // reactively update in a pushed screen, so a badge would be a false
                // negative more often than not. Revisit with a per-item lookup.
              ),
            ),
          ),
        )
        .then((_) => afterReturn());
  }

  void openList(BuildContext context, HomeListSection section) {
    final Widget screen;
    if (section.isTrakt) {
      screen = TraktSeeAllScreen(
        initialList: section.traktChoice,
        cwItems: List<StremioMeta>.of(traktItems()),
        cwProgress: traktProgress(),
        onOpen: openTraktItem,
        onQuickPlay: pikpakOnly() ? null : playTraktItem,
        isBound: isBound,
        isTelevision: isTelevision(),
      );
    } else if (section.isMdblist) {
      screen = MdblistSeeAllScreen(
        initialList: section.mdblistList,
        initialListIsPublic: section.rowId.startsWith(
          HomeExtraRowIds.mdblistTopPrefix,
        ),
        onOpen: openMdblist,
        onQuickPlay: pikpakOnly() ? null : playMdblist,
        isBound: isBound,
        isTelevision: isTelevision(),
      );
    } else {
      screen = SimklSeeAllScreen(
        initialList: section.simklList,
        cwItems: List<StremioMeta>.of(simklItems()),
        cwProgress: simklProgress(),
        onOpen: openSimklItem,
        onQuickPlay: pikpakOnly() ? null : playSimklItem,
        cwOnOpen: openSimklCwItem,
        cwOnQuickPlay: pikpakOnly() ? null : playSimklCwItem,
        isBound: isBound,
        isTelevision: isTelevision(),
      );
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => wrap(screen)))
        // trackers:true — this grid renders the tracker's own lists, and a
        // played title must reflect on return (same as _openTraktSeeAll).
        .then((_) => afterTrackerReturn());
  }

  void pushContinuation(
    BuildContext context, {
    required String title,
    required String initialCategory,
    required List<StremioMeta> items,
    required double? Function(StremioMeta) progressOf,
    required void Function(StremioMeta) onOpen,
    required void Function(StremioMeta)? onQuickPlay,
    required Future<List<StremioMeta>> Function()? onReload,
    VoidCallback? onReturn,
  }) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => wrap(
              ContinueWatchingSeeAllScreen(
                title: title,
                initialCategory: initialCategory,
                items: List<StremioMeta>.of(items),
                progressOf: progressOf,
                onOpen: onOpen,
                onQuickPlay: onQuickPlay,
                onReload: onReload,
                // CW items are all rail-loaded, so _boundCounts covers them.
                isBound: isBound,
                isTelevision: isTelevision(),
              ),
            ),
          ),
        )
        .then((_) => onReturn?.call());
  }

  void openTrakt(BuildContext context, [String initialCategory = 'all']) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => wrap(
              TraktSeeAllScreen(
                initialCategory: initialCategory,
                cwItems: List<StremioMeta>.of(traktItems()),
                // Pass the live progress map (read-only in the screen) so resume
                // bars reflect any refresh while the screen is open, matching the
                // old live-closure behaviour; items stay a snapshot so the grid
                // doesn't shift under the user.
                cwProgress: traktProgress(),
                onOpen: openTraktItem,
                onQuickPlay: pikpakOnly() ? null : playTraktItem,
                // CW items are all rail-loaded, so _boundCounts covers them.
                isBound: isBound,
                isTelevision: isTelevision(),
              ),
            ),
          ),
        )
        .then((_) => afterTrackerReturn());
  }
}
