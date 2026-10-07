import 'dart:async';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection_state.dart';
import 'package:debrify/models/alldebrid_file.dart';
import 'package:debrify/models/alldebrid_link.dart';
import 'package:debrify/models/alldebrid_magnet.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:debrify/widgets/cloud/cloud_row_skeleton.dart';
import 'package:flutter/material.dart';

typedef AllDebridListViewsDeps = ({
  AllDebridSearchState searchState,
  AllDebridFocusState focusState,
  AllDebridSelectionState selectionState,
  AllDebridLibraryState libraryState,
  AllDebridNavigationState navigationState,
  BuildContext Function() context,
  bool Function() mounted,
  Future<void> Function(SeriesSource)? Function() onSourceSelected,
  bool Function() selectSourceMode,
  Future<void> Function(AllDebridMagnet magnet) addMagnetToPlaylist,
  Widget Function(AllDebridFile f, int index) buildFileCard,
  Widget Function(AllDebridLink l, int index) buildLinkCard,
  Widget Function(AllDebridMagnet m, int index) buildMagnetCard,
  Future<void> Function(AllDebridLink l) copyLink,
  Future<void> Function(List<AllDebridLink> links, {String? title}) deleteLinks,
  Future<void> Function(List<AllDebridMagnet> magnets, {String? title})
  deleteMagnets,
  Future<void> Function(AllDebridFile file) downloadFile,
  Future<void> Function(AllDebridLink l) downloadLink,
  Future<void> Function(AllDebridMagnet magnet) downloadMagnet,
  Future<void> Function() load,
  Future<void> Function() loadLinks,
  bool Function(AllDebridFile f) looksLikeVideo,
  Future<void> Function(AllDebridMagnet magnet, {bool force}) openMagnet,
  Future<void> Function(AllDebridFile file) playFile,
  Future<void> Function(AllDebridLink l) playLink,
  Future<void> Function(AllDebridMagnet magnet) playMagnet,
  void Function(String message, {bool isError}) snack,
  void Function(String id) toggleSelection,
  List<AllDebridFile> Function() visibleFiles,
  List<AllDebridLink> Function() visibleLinks,
  List<AllDebridMagnet> Function() visibleMagnets,
});

class AllDebridListViews {
  final AllDebridListViewsDeps _deps;
  AllDebridListViews(this._deps);
  AllDebridSearchState get _search => _deps.searchState;
  AllDebridFocusState get _f => _deps.focusState;
  AllDebridSelectionState get _selection => _deps.selectionState;
  AllDebridLibraryState get _library => _deps.libraryState;
  AllDebridNavigationState get _navigation => _deps.navigationState;

  Widget buildMagnetsView() {
    final app = AppThemeScope.of(_deps.context());
    final magnets = _deps.visibleMagnets();
    if (magnets.isEmpty) {
      return RefreshIndicator(
        onRefresh: _deps.load,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Text(
                _search.searchQuery.isNotEmpty
                    ? 'No magnets match your search.'
                    : 'Your AllDebrid library is empty.',
                style: TextStyle(color: app.fade(app.core.tx, 0x8A / 0xFF)),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _deps.load,
      child: ListView.builder(
        controller: _f.scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: magnets.length,
        itemBuilder: (context, index) {
          return KeyedSubtree(
            key: ValueKey(magnets[index].id),
            child: _deps.buildMagnetCard(magnets[index], index),
          );
        },
      ),
    );
  }

  Widget buildMagnetCard(AllDebridMagnet m, int index) {
    if (_deps.selectSourceMode()) {
      return CloudFileRow(
        kind: CloudRowKind.folder,
        title: m.name.isEmpty ? '(unnamed)' : m.name,
        meta: Formatters.formatFileSize(m.size),
        badges: const [CloudRowBadge('Ready', CloudBadgeKind.ok)],
        onTap: () async {
          if (m.hash.trim().isEmpty) {
            _deps.snack(
              'This AllDebrid magnet has no infohash to bind.',
              isError: true,
            );
            return;
          }
          await _deps.onSourceSelected()?.call(
            SeriesSource(
              torrentHash: m.hash,
              torrentName: m.name,
              debridService: 'alldebrid',
              debridTorrentId: m.id,
              boundAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
          if (!_deps.mounted()) return;
          Navigator.of(_deps.context()).pop();
        },
        focusNode: index == 0 ? _f.firstItemFocusNode : null,
      );
    }

    // Same action set (labels, conditions) the old Open/Play pills + ⋮ menu
    // offered; the row's tap now carries Open for ready magnets.
    final actions = <CloudRowAction>[
      if (m.isReady)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () => _deps.playMagnet(m),
        ),
      if (m.isReady)
        CloudRowAction(
          icon: Icons.download,
          label: 'Download to device',
          showInStrip: true,
          onSelected: () => _deps.downloadMagnet(m),
        ),
      if (m.isReady)
        CloudRowAction(
          icon: Icons.folder_open,
          label: 'Open',
          onSelected: () => _deps.openMagnet(m),
        ),
      if (m.isReady)
        CloudRowAction(
          icon: Icons.playlist_add,
          label: 'Add to Playlist',
          onSelected: () => _deps.addMagnetToPlaylist(m),
        ),
      CloudRowAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onSelected: () => _deps.deleteMagnets([m]),
      ),
    ];

    return CloudFileRow(
      kind: m.isError ? CloudRowKind.error : CloudRowKind.folder,
      title: m.name.isEmpty ? '(unnamed)' : m.name,
      meta: m.isReady ? Formatters.formatFileSize(m.size) : null,
      badges: [
        if (m.isError)
          const CloudRowBadge('Failed', CloudBadgeKind.error)
        else if (!m.isReady)
          CloudRowBadge(
            'Downloading ${m.progressPercent}%',
            CloudBadgeKind.warn,
          ),
      ],
      // Not-ready magnets keep a tap action too: _openMagnet explains why it
      // can't open ("still downloading" / "failed") — better than the menu
      // fallback, which here would be a Delete-only menu.
      onTap: () => _deps.openMagnet(m),
      actions: actions,
      selectionMode: _selection.selectionMode,
      selected: _selection.selectedIds.contains(m.id),
      onToggleSelected: () => _deps.toggleSelection(m.id),
      focusNode: index == 0 ? _f.firstItemFocusNode : null,
    );
  }

  Widget buildLinksView() {
    final app = AppThemeScope.of(_deps.context());
    if (_library.loadingLinks) {
      return const CloudRowSkeletonList();
    }
    if (_library.linksError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off,
                size: 48,
                color: app.fade(app.core.tx, 0x62 / 0xFF),
              ),
              const SizedBox(height: 16),
              Text(_library.linksError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _deps.loadLinks,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final links = _deps.visibleLinks();
    if (links.isEmpty) {
      return RefreshIndicator(
        onRefresh: _deps.loadLinks,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Text(
                _search.searchQuery.isNotEmpty
                    ? 'No links match your search.'
                    : 'No saved links yet.',
                style: TextStyle(color: app.fade(app.core.tx, 0x8A / 0xFF)),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _deps.loadLinks,
      child: ListView.builder(
        controller: _f.scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: links.length,
        itemBuilder: (context, index) {
          return KeyedSubtree(
            key: ValueKey(links[index].link),
            child: _deps.buildLinkCard(links[index], index),
          );
        },
      ),
    );
  }

  Widget buildLinkCard(AllDebridLink l, int index) {
    final isVideo = FileUtils.isVideoFile(l.fileName);
    final subtitle = [
      if (l.size > 0) Formatters.formatFileSize(l.size),
      if (l.host.isNotEmpty) l.host,
    ].join(' · ');

    if (_deps.selectSourceMode()) {
      return CloudFileRow(
        kind: isVideo ? CloudRowKind.video : CloudRowKind.file,
        title: l.fileName,
        meta: subtitle.isEmpty ? null : subtitle,
        onTap: isVideo
            ? () async {
                await _deps.onSourceSelected()?.call(
                  SeriesSource(
                    torrentHash: '',
                    torrentName: l.fileName,
                    debridService: 'alldebrid',
                    debridTorrentId: SeriesSource.opaqueCloudReference(l.link),
                    cloudSourceKind: SeriesSource.cloudKindWebDownload,
                    boundAt: DateTime.now().millisecondsSinceEpoch,
                  ),
                );
                if (!_deps.mounted()) return;
                Navigator.of(_deps.context()).pop();
              }
            : null,
        focusNode: index == 0 ? _f.firstItemFocusNode : null,
      );
    }

    final actions = <CloudRowAction>[
      if (isVideo)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () => _deps.playLink(l),
        ),
      CloudRowAction(
        icon: Icons.download_rounded,
        label: isVideo ? 'Download to device' : 'Download',
        showInStrip: true,
        onSelected: () => _deps.downloadLink(l),
      ),
      CloudRowAction(
        icon: Icons.link,
        label: 'Copy link',
        onSelected: () => _deps.copyLink(l),
      ),
      CloudRowAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onSelected: () => _deps.deleteLinks([l]),
      ),
    ];

    return CloudFileRow(
      kind: isVideo ? CloudRowKind.video : CloudRowKind.file,
      title: l.fileName,
      meta: subtitle.isEmpty ? null : subtitle,
      onTap: isVideo ? () => _deps.playLink(l) : null,
      actions: actions,
      focusNode: index == 0 ? _f.firstItemFocusNode : null,
    );
  }

  Widget buildFilesView() {
    final app = AppThemeScope.of(_deps.context());
    if (_navigation.loadingFiles) {
      return const CloudRowSkeletonList();
    }
    final files = _deps.visibleFiles();
    if (files.isEmpty) {
      return Center(
        child: Text(
          _search.fileSearchQuery.isNotEmpty
              ? 'No files match your search.'
              : 'No files in this magnet.',
          style: TextStyle(color: app.fade(app.core.tx, 0x8A / 0xFF)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: files.length,
      itemBuilder: (context, index) {
        return KeyedSubtree(
          key: ValueKey(
            '${_navigation.currentMagnet!.id}:${files[index].path}:$index',
          ),
          child: _deps.buildFileCard(files[index], index),
        );
      },
    );
  }

  Widget buildFileCard(AllDebridFile f, int index) {
    final isVideo = _deps.looksLikeVideo(f);

    // Parity with the old card: files inside a magnet only offer Play (video)
    // and Download — no delete or playlist at file granularity.
    final actions = <CloudRowAction>[
      if (isVideo)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () => _deps.playFile(f),
        ),
      CloudRowAction(
        icon: Icons.download_rounded,
        label: 'Download',
        showInStrip: true,
        onSelected: () => _deps.downloadFile(f),
      ),
    ];

    return CloudFileRow(
      kind: isVideo ? CloudRowKind.video : CloudRowKind.file,
      title: f.fileName,
      meta: Formatters.formatFileSize(f.size),
      onTap: isVideo ? () => _deps.playFile(f) : null,
      actions: actions,
      focusNode: index == 0 ? _f.firstItemFocusNode : null,
    );
  }
}
