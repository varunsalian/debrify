import 'package:debrify/features/debrid_downloads/models/debrid_downloads_view.dart';
import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/widgets/cloud/cloud_theme.dart';
import 'package:flutter/material.dart';

import 'debrid_catalog_state.dart';
import 'debrid_focus_state.dart';
import 'debrid_navigation_state.dart';

typedef DebridRootLayoutDeps = ({
  DebridNavigationState navigationState,
  Widget Function() buildFolderBrowserScaffold,
  DebridCatalogState catalogState,
  Widget Function() buildTorrentContent,
  Widget Function() buildDownloadContent,
  DebridFocusState focusState,
  bool Function() isPushedRoute,
  bool Function() selectSourceMode,
  RDTorrent? Function() initialTorrentForOptions,
});

class DebridRootLayout {
  DebridRootLayout(this._deps);
  final DebridRootLayoutDeps _deps;

  Widget build(BuildContext context) {
    // When DEEP-LINKED into a specific torrent (pushed WITH a target) and still
    // at root, show the loading state while we navigate into it. When browsing
    // from the Cloud hub there's no target, so the torrents-list root is the
    // real content — don't gate it behind a spinner.
    if (_deps.isPushedRoute() &&
        !_deps.selectSourceMode() &&
        _deps.initialTorrentForOptions() != null &&
        _deps.navigationState.currentTorrentId == null) {
      return CloudScaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back',
          ),
          title: const Text('Opening torrent...'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading torrent files...'),
            ],
          ),
        ),
      );
    }

    // If in folder browsing mode, show folder view
    if (_deps.navigationState.currentTorrentId != null) {
      return _deps.buildFolderBrowserScaffold();
    }

    final Widget content =
        _deps.catalogState.selectedView == DebridDownloadsView.torrents
        ? _deps.buildTorrentContent()
        : _deps.buildDownloadContent();

    return CloudScaffold(
      appBar: _deps.selectSourceMode()
          ? AppBar(
              leading: IconButton(
                focusNode: _deps.focusState.backButtonFocusNode,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Back',
              ),
              title: const Text('Select Source from Real-Debrid'),
            )
          : null,
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}
