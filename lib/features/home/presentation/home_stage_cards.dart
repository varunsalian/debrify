import 'package:flutter/material.dart';
import '../../../models/home_collection_rows.dart';
import '../../../models/stremio_addon.dart';
import 'home_board_cell.dart';
import 'home_stage_rows.dart';
import 'home_catalog_item_actions.dart';

/// Shared stage title-card composition and action dispatch. The host owns the
/// current catalog, focus history and accepted actions; this object owns no
/// resources. Layouts supply their directional grammar and extra focus effects.
class HomeStageCards {
  const HomeStageCards({
    required this.sectionAt,
    required this.collectionFor,
    required this.aspectOf,
    required this.artOf,
    required this.items,
    required this.openContinuationMenu,
    required this.onFocused,
    required this.focusSidebar,
    required this.switchRail,
    required this.loadMore,
  });

  final CatalogSection Function(int) sectionAt;
  final HomeCollectionSection? Function(HomeRail) collectionFor;
  final double Function(HomeRail, {double? fallback}) aspectOf;
  final String? Function(HomeRail, StremioMeta, {bool wide}) artOf;
  final HomeCatalogItemActions items;
  final void Function(HomeContinuationRow, StremioMeta, int, int)
  openContinuationMenu;
  final void Function(String, StremioMeta, int) onFocused;
  final VoidCallback focusSidebar;
  final ValueChanged<int> switchRail;
  final ValueChanged<int> loadMore;

  HomeBoardCell build({
    required HomeRail rail,
    required String railKey,
    required StremioMeta item,
    required List<FocusNode> nodes,
    required int column,
    // Atrium historically resolves its borrowed row at action time. Other
    // layouts retain the item captured when their cell was built.
    StremioMeta Function()? readActionItem,
    bool wide = false,
    Color? restVeil,
    bool pageNearEnd = true,
    VoidCallback? onUp,
    VoidCallback? onDown,
    VoidCallback? onUpHold,
    VoidCallback? onDownHold,
    VoidCallback? onLeft,
    VoidCallback? onRight,
    VoidCallback? onFocusedExtra,
  }) {
    final collection = collectionFor(rail);
    StremioMeta actionItem() => readActionItem?.call() ?? item;
    return HomeBoardCell(
      onLeftEdge: focusSidebar,
      item: item,
      isTelevision: true,
      focusNode: nodes[column],
      column: column,
      rowNodes: nodes,
      hasBoundSource: items.isBound(item),
      // Stage layouts use white; Classic retains its own focus treatment.
      ringColor: Colors.white,
      aspectRatio: aspectOf(rail, fallback: wide ? 16 / 9 : null),
      artUrl: artOf(rail, item, wide: wide),
      focusArtUrl: collection?.focusArtOf(item),
      focusVideoUrl: collection?.focusVideoOf(item),
      focusGlowEnabled: collection?.collection.focusGlowEnabled ?? false,
      showTitleOverlay: !(collection?.folderOf(item)?.hideTitle ?? false),
      restVeil: restVeil,
      progress: rail.cw?.progressOf(item),
      episodeLabel: rail.cw?.episodeOf(item),
      onQuickPlay: rail.cw != null || items.pikpakOnly
          ? null
          : () => items.quickPlay(sectionAt(rail.sectionIndex!), actionItem()),
      onLongPress: rail.cw == null
          ? null
          : () => openContinuationMenu(
              rail.cw!,
              actionItem(),
              rail.cwIndex,
              column,
            ),
      onFocused: () {
        onFocused(railKey, actionItem(), column);
        onFocusedExtra?.call();
      },
      onUp: onUp ?? () => switchRail(-1),
      onDown: onDown ?? () => switchRail(1),
      onUpHold: onUpHold,
      onDownHold: onDownHold,
      onLeft: onLeft,
      onRight: onRight,
      onOpen: () {
        if (rail.cw != null) {
          rail.cw!.onOpen(actionItem());
        } else {
          items.open(sectionAt(rail.sectionIndex!), actionItem());
        }
      },
      onNearEnd: !pageNearEnd || rail.sectionIndex == null
          ? null
          : () => loadMore(rail.sectionIndex!),
    );
  }
}
