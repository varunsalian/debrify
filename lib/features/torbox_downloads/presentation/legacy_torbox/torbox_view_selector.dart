import 'package:debrify/features/torbox_downloads/presentation/torbox_downloads_view.dart';
import 'package:debrify/widgets/cloud/cloud_segmented_tabs.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';
import 'torbox_selection_state.dart';
import 'torbox_torrent_search_state.dart';

typedef TorboxViewSelectorDeps = ({
  TorboxCatalogState catalogState,
  void Function() resetListScroll,
  void Function(VoidCallback) setState,
  TorboxTorrentSearchState torrentSearchState,
  TorboxSelectionState selectionState,
});

class TorboxViewSelector {
  TorboxViewSelector(this._deps);
  final TorboxViewSelectorDeps _deps;

  /// Full-width view switcher on its own line under the toolbar (two labels
  /// don't fit the toolbar slot the old single-label dropdown used).
  Widget buildViewSelectorBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: CloudSegmentedTabs<TorboxDownloadsView>(
        segments: const [
          CloudSegment(
            TorboxDownloadsView.torrents,
            'Torrents',
            Icons.folder_rounded,
          ),
          CloudSegment(
            TorboxDownloadsView.webDownloads,
            'Web Downloads',
            Icons.link_rounded,
          ),
        ],
        selected: _deps.catalogState.selectedView,
        onSelected: (value) {
          if (value == _deps.catalogState.selectedView) return;
          // The two root lists swap in the same element slot, so the incoming
          // one would inherit the outgoing list's scroll offset.
          _deps.resetListScroll();
          _deps.setState(() {
            _deps.catalogState.selectedView = value;
            // Source-selection mode arrives with torrent title search active.
            // Suspend that search while Web Downloads is selected, then
            // restore it if the user switches back to Torrents.
            _deps.torrentSearchState.isTorrentSearchActive =
                value == TorboxDownloadsView.torrents &&
                _deps.torrentSearchState.torrentSearchController.text
                    .trim()
                    .isNotEmpty;
            // Exit selection mode when switching views
            if (_deps.selectionState.isSelectionMode) {
              _deps.selectionState.isSelectionMode = false;
              _deps.selectionState.selectedTorrentIds.clear();
              _deps.selectionState.selectedWebDownloadIds.clear();
            }
          });
        },
      ),
    );
  }
}
