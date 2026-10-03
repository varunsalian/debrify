import 'package:debrify/models/torbox_torrent.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';

typedef TorboxInitialActionDeps = ({
  TorboxCatalogState catalogState,
  bool Function() mounted,
  void Function(TorboxTorrent torrent) navigateIntoTorrent,
});

class TorboxInitialAction {
  TorboxInitialAction(this._deps);
  final TorboxInitialActionDeps _deps;

  void maybeTriggerInitialAction() {
    if (_deps.catalogState.initialActionHandled) {
      return;
    }
    final pendingTorrent = _deps.catalogState.pendingInitialTorrent;
    if (pendingTorrent == null) {
      return;
    }

    // Try to find the torrent in the loaded list first
    TorboxTorrent? target;
    for (final torrent in _deps.catalogState.torrents) {
      if (torrent.id == pendingTorrent.id) {
        target = torrent;
        break;
      }
    }

    // If not found in list, use the pending torrent directly
    // (it already has all the data from the API response)
    target ??= pendingTorrent;

    _deps.catalogState.initialActionHandled = true;
    _deps.catalogState.pendingInitialTorrent = null;

    final selected = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted()) return;
      // Navigate directly into the torrent folder instead of showing popups
      // This matches the Real-Debrid behavior
      _deps.navigateIntoTorrent(selected);
    });
  }
}
