import 'package:flutter/widgets.dart';

import '../../../models/stremio_addon.dart';
import '../data/home_catalog_origin_repository.dart';
import '../models/home_catalog_origin.dart';
import 'home_detail_route.dart';
import 'home_unavailable_origin_dialog.dart';

/// Opens one catalog detail route using borrowed data and presentation actions.
/// Preparing the builder before push preserves opening-time menu/layout snapshots.
class HomeDetailNavigation {
  const HomeDetailNavigation(this.origin);

  final HomeCatalogOriginRepository origin;

  Future<void> open({
    required BuildContext context,
    required StremioMeta item,
    required StremioAddon addon,
    required String routeName,
    required bool Function() isCurrent,
    required bool Function(StremioMeta) hasLocalHistory,
    required Future<bool> Function(String) removeLocalHistory,
    required Future<void> Function() onHistoryRemoved,
    required void Function(String) showMessage,
    required VoidCallback onClosed,
    required WidgetBuilder Function(
      StremioMeta item,
      StremioAddon addon,
      HomeDetailRoute route,
    )
    prepareBuilder,
  }) async {
    bool current() => context.mounted && isCurrent();
    if (!current()) return;
    final prepared = await origin.prepare(item, addon, isCurrent: current);
    if (!context.mounted ||
        !current() ||
        prepared.status == HomeCatalogOriginStatus.retired) {
      return;
    }
    if (prepared.status == HomeCatalogOriginStatus.unverified) {
      showMessage('Could not verify series episodes. Please retry.');
      return;
    }
    final resolvedItem = prepared.item;
    final resolvedAddon = prepared.addon;
    if (resolvedAddon == null) {
      final remove = await confirmHomeUnavailableOriginRemoval(
        context: context,
        title: resolvedItem.name,
        canRemove: () => hasLocalHistory(resolvedItem),
        isCurrent: current,
      );
      if (!current() || !remove) return;
      if (!await removeLocalHistory(resolvedItem.imdbId!) || !current()) return;
      await onHistoryRemoved();
      return;
    }
    final route = HomeDetailRoute(
      name: routeName,
      isOwnerCurrent: current,
      onClosed: onClosed,
    );
    final builder = prepareBuilder(resolvedItem, resolvedAddon, route);
    if (!context.mounted || !current()) return;
    await route.push(Navigator.of(context), builder);
  }
}
