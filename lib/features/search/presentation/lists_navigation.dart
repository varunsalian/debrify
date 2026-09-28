import 'package:flutter/material.dart';
import '../../../models/mdblist_list_choice.dart';
import '../../../models/stremio_addon.dart';
import '../../../screens/see_all/mdblist_lists_see_all_screen.dart';
import '../../../screens/see_all/mdblist_see_all_screen.dart';

/// Lists grid → items navigation preserves the covering route's navigator and
/// snapshots the search results. Playback and return refresh remain host actions.
class ListsNavigation {
  const ListsNavigation({
    required this.isTelevision,
    required this.pikpakOnly,
    required this.isBound,
    required this.onOpen,
    required this.onQuickPlay,
    required this.afterReturn,
  });

  final bool Function() isTelevision;
  final bool Function() pikpakOnly;
  final bool Function(StremioMeta) isBound;
  final ValueChanged<StremioMeta> onOpen;
  final ValueChanged<StremioMeta> onQuickPlay;
  final VoidCallback afterReturn;

  void openGrid(
    BuildContext context,
    String query,
    List<MdblistListChoice> lists,
  ) {
    final results = List<MdblistListChoice>.of(lists);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (gridContext) => MdblistListsSeeAllScreen(
          query: query,
          lists: results,
          isTelevision: isTelevision(),
          onOpen: (list) => openItems(gridContext, list),
        ),
      ),
    );
  }

  void openItems(
    BuildContext context,
    MdblistListChoice list, {
    VoidCallback? onReturn,
  }) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => MdblistSeeAllScreen(
              initialList: list,
              isTelevision: isTelevision(),
              isBound: isBound,
              onOpen: onOpen,
              onQuickPlay: pikpakOnly() ? null : onQuickPlay,
            ),
          ),
        )
        .then((_) {
          afterReturn();
          onReturn?.call();
        });
  }
}
