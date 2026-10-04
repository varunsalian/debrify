import 'dart:async';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_dependencies.dart';
import 'package:debrify/services/storage/watchlist_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CatalogDetailWatchlist {
  final CatalogDetailDependencies _deps;

  CatalogDetailWatchlist(this._deps);

  bool get supportsMyWatchlist =>
      WatchlistStorage.supportsMyWatchlistItem(_deps.presentedItem());

  bool inMyWatchlist = false;

  Future<void> loadMyWatchlistState() async {
    if (!supportsMyWatchlist) return;
    final saved = await WatchlistStorage.isInMyWatchlist(_deps.presentedItem());
    if (!_deps.mounted() || saved == inMyWatchlist) return;
    _deps.setState(() => inMyWatchlist = saved);
  }

  Future<void> toggleMyWatchlist() async {
    if (!supportsMyWatchlist) return;
    final next = !inMyWatchlist;
    _deps.setState(() => inMyWatchlist = next);
    try {
      final sourceAddon =
          _deps.presentedItem().sourceAddon ?? _deps.item().sourceAddon;
      final savedItem = sourceAddon == null
          ? _deps.presentedItem()
          : _deps.presentedItem().withSourceAddon(sourceAddon);
      await WatchlistStorage.setMyWatchlistItem(savedItem, next);
      if (!_deps.mounted()) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(_deps.context())
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              next ? 'Added to My Watchlist' : 'Removed from My Watchlist',
            ),
          ),
        );
    } catch (_) {
      if (!_deps.mounted()) return;
      _deps.setState(() => inMyWatchlist = !next);
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text('Couldn\'t update My Watchlist')),
      );
    }
  }
}
