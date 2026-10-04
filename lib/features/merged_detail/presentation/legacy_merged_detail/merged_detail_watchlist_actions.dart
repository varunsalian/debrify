import 'dart:async';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_state.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/storage/watchlist_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MergedDetailWatchlistActions {
  final MergedDetailDependencies _deps;
  MergedDetailWatchlistActions(this._deps);
  StremioMeta get _item => _deps.presentedItem();
  bool get mounted => _deps.mounted();
  void Function(VoidCallback) get setState => _deps.setState;
  MergedDetailTrackingState get _k => _deps.parts.trackingState;

  bool get supportsMyWatchlist =>
      WatchlistStorage.supportsMyWatchlistItem(_item);
  StremioMeta get myWatchlistItem => WatchlistStorage.withMyWatchlistSource(
    _item,
    _deps.item().sourceAddon ?? _deps.addon(),
  );

  Future<void> loadMyWatchlistState() async {
    if (!supportsMyWatchlist) return;
    final saved = await WatchlistStorage.isInMyWatchlist(myWatchlistItem);
    if (!mounted || saved == _k.inMyWatchlist) return;
    setState(() => _k.inMyWatchlist = saved);
  }

  Future<void> toggleMyWatchlist() async {
    if (!supportsMyWatchlist) return;
    final next = !_k.inMyWatchlist;
    setState(() => _k.inMyWatchlist = next);
    try {
      await WatchlistStorage.setMyWatchlistItem(myWatchlistItem, next);
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() => _k.inMyWatchlist = !next);
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text('Couldn\'t update My Watchlist')),
      );
    }
  }
}
