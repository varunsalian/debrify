import 'dart:async';

import 'package:debrify/features/iptv/application/iptv_status_chip_types.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart' show TvHeldKeyGuard;
import 'package:debrify/widgets/iptv/db_channel_list.dart';
import 'package:flutter/material.dart';

typedef IptvCategoriesDeps = ({
  IptvCatalogState catalogState,
  void Function() applyFilters,
  // TEMP(iptv): _categoryCounts -> IptvRowProjection.categoryCounts (step 6).
  Map<String, int> Function() categoryCounts,
  BuildContext Function() context,
  List<String> Function(CatalogSnapshot snap, List<CatalogGroup> groups)
  deriveCategories,
  DbChannelList Function(CatalogSnapshot snap, {String? group, String? search})
  makeDbList,
  bool Function() mounted,
  StateSetter setState,
  void Function(
    CatalogChipState state,
    String message, {
    Duration? autoHide,
    ChipOwner owner,
  })
  showChip,
});

class IptvCategories {
  final IptvCategoriesDeps _deps;
  final IptvCatalogState _catalogState;

  IptvCategories(this._deps) : _catalogState = _deps.catalogState;

  Map<String, int> get _categoryCounts => _deps.categoryCounts();

  /// Whether categories can be customized in the current view.
  ///
  /// Only catalog-backed sources (M3U / Xtream) qualify: the hidden set is
  /// keyed by catalog, and the virtual shelves (Favorites, custom lists,
  /// Continue watching), Stremio addons and imported files never get one —
  /// they stay materialized in memory. Everything downstream of this getter
  /// can assume [dbSnapshot] is non-null.
  bool get canShowCategoryOptions => _catalogState.dbSnapshot != null;

  /// Hold-OK (TV) or long-press (touch) on a category: make it the source's
  /// default landing category, or hide it. Routed from the same gestures that
  /// used to jump straight to the hide confirmation; hide still confirms
  /// through [_promptHideCategory], so its wording and semantics are
  /// unchanged.
  Future<void> promptCategoryOptions(String category) async {
    final app = AppThemeScope.of(_deps.context());
    final snap = _catalogState.dbSnapshot;
    if (snap == null || category.isEmpty) return;
    final isDefault =
        IptvCatalogDb.defaultCategory(snap.catalogKey) == category;
    final action = await showDialog<String>(
      context: _deps.context(),
      builder: (dialogContext) => TvHeldKeyGuard(
        child: SimpleDialog(
          backgroundColor: app.iptv.modalBg,
          title: Text(
            category,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: app.core.tx, fontWeight: FontWeight.w700),
          ),
          children: [
            ListTile(
              autofocus: true,
              leading: Icon(
                isDefault
                    ? Icons.bookmark_remove_rounded
                    : Icons.bookmark_added_rounded,
                color: app.core.tx,
              ),
              title: Text(
                isDefault ? 'Clear default category' : 'Set as default',
                style: TextStyle(color: app.core.tx),
              ),
              subtitle: Text(
                isDefault
                    ? 'This source goes back to opening on its first category'
                    : 'Open this source on "$category"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: app.core.tx.withAlpha(0xB3)),
              ),
              onTap: () => Navigator.of(
                dialogContext,
              ).pop(isDefault ? 'clearDefault' : 'setDefault'),
            ),
            ListTile(
              leading: Icon(Icons.visibility_off_outlined, color: app.core.tx),
              title: Text(
                'Hide category…',
                style: TextStyle(color: app.core.tx),
              ),
              onTap: () => Navigator.of(dialogContext).pop('hide'),
            ),
          ],
        ),
      ),
    );
    if (!_deps.mounted()) return;
    switch (action) {
      case 'setDefault':
        if (IptvCatalogDb.setDefaultCategory(snap.catalogKey, category)) {
          _deps.showChip(
            CatalogChipState.success,
            'Opens on "$category" from now on',
            autoHide: const Duration(milliseconds: 2500),
          );
        } else {
          _deps.showChip(
            CatalogChipState.failure,
            'Couldn\'t save the default — try again',
            autoHide: const Duration(milliseconds: 3500),
          );
        }
      case 'clearDefault':
        if (IptvCatalogDb.setDefaultCategory(snap.catalogKey, null)) {
          _deps.showChip(
            CatalogChipState.success,
            'Default category cleared',
            autoHide: const Duration(milliseconds: 2500),
          );
        } else {
          _deps.showChip(
            CatalogChipState.failure,
            'Couldn\'t clear the default — try again',
            autoHide: const Duration(milliseconds: 3500),
          );
        }
      case 'hide':
        await promptHideCategory(category);
    }
  }

  /// Hide [category] from this source, after confirming.
  ///
  /// The gesture that gets here is a HOLD (TV) or long-press (touch) on the
  /// category in a picker — deliberately confirmed rather than instant, since
  /// it's a destructive-looking change reached from a control whose normal
  /// press just selects.
  Future<void> promptHideCategory(String category) async {
    final app = AppThemeScope.of(_deps.context());
    final snap = _catalogState.dbSnapshot;
    if (snap == null || category.isEmpty) return;
    final count = _categoryCounts[category] ?? 0;
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (dialogContext) => AlertDialog(
        backgroundColor: app.iptv.modalBg,
        title: Text(
          'Hide this category?',
          style: TextStyle(color: app.core.tx, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '$category\n\n'
          '${count == 0 ? 'Its channels' : '$count channel'
                    '${count == 1 ? '' : 's'}'} '
          'will stop showing up in IPTV — in the list, in search and in the '
          'player\'s guide. Nothing is deleted: bring it back any time from '
          'Settings › IPTV › Hidden categories.',
          style: TextStyle(color: app.core.tx.withAlpha(0xB3), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hide'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_deps.mounted()) return;
    if (!IptvCatalogDb.setGroupHidden(snap.catalogKey, category, true)) {
      _deps.showChip(
        CatalogChipState.failure,
        'Couldn\'t hide "$category" — try again',
        autoHide: const Duration(milliseconds: 3500),
      );
      return;
    }
    await refreshAfterHiddenChange();
    if (!_deps.mounted()) return;
    _deps.showChip(
      CatalogChipState.success,
      'Hid "$category"',
      autoHide: const Duration(milliseconds: 2600),
    );
  }

  /// Re-derive the category list, its counts and the row facades after the
  /// hidden set changed.
  ///
  /// The rows themselves are untouched, so the shared instance cache is kept:
  /// it's keyed by catalog POSITION, which a hidden category doesn't move
  /// (positions are stored column values, not list offsets). Surviving rows
  /// therefore keep their instance, ObjectKey and focus node instead of being
  /// torn down and rebuilt.
  Future<void> refreshAfterHiddenChange() async {
    final snap = _catalogState.dbSnapshot;
    if (snap == null) return;
    final ticket = _catalogState.loadTicket;
    final groups = await IptvCatalogDb.groupsAsync(snap);
    if (!_deps.mounted() || ticket != _catalogState.loadTicket) return;
    final categories = _deps.deriveCategories(snap, groups);
    _deps.setState(() {
      _catalogState.dbGroupCounts = {
        for (final g in groups)
          if (g.name != null && g.name!.isNotEmpty) g.name!: g.count,
      };
      _catalogState.categories = categories;
      _catalogState.allChannels = _deps.makeDbList(snap);
      // The selected category is the one most likely to have just been
      // hidden — fall back to All rather than leaving the filter pinned to
      // something the list no longer offers.
      if (_catalogState.selectedCategory != null &&
          !categories.contains(_catalogState.selectedCategory)) {
        _catalogState.selectedCategory = null;
      }
    });
    _deps.applyFilters();
  }
}
