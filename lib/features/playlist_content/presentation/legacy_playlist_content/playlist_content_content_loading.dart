import 'dart:async';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_catalog_state.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/utils/rd_folder_tree_builder.dart';
import 'package:debrify/utils/torbox_folder_tree_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PlaylistContentContentLoadingDeps = ({
  void Function(VoidCallback) setState,
  PlaylistContentCatalogState catalogState,
  Map<String, dynamic> Function() playlistItem,
  Future<void> Function() loadPikPakContent,
  Future<void> Function() loadWebDavContent,
  Future<void> Function() loadPremiumizeContent,
  bool Function() mounted,
});

class PlaylistContentContentLoading {
  PlaylistContentContentLoading(this._deps);
  final PlaylistContentContentLoadingDeps _deps;

  /// Load content from provider
  Future<void> loadContent() async {
    _deps.setState(() {
      _deps.catalogState.isLoading = true;
      _deps.catalogState.errorMessage = null;
    });

    try {
      final provider =
          (_deps.playlistItem()['provider'] as String?) ?? 'realdebrid';

      final normalizedProvider = provider.toLowerCase();
      if (normalizedProvider == 'torbox') {
        await loadTorboxContent();
      } else if (normalizedProvider == 'pikpak') {
        await _deps.loadPikPakContent();
      } else if (normalizedProvider == 'webdav') {
        await _deps.loadWebDavContent();
      } else if (normalizedProvider == 'premiumize') {
        await _deps.loadPremiumizeContent();
      } else if (normalizedProvider == 'alldebrid') {
        await loadAllDebridContent();
      } else {
        await loadRealDebridContent();
      }

      // Note: View mode is now applied in _initializeScreen() after _parseSeriesPlaylist()
      // This ensures _seriesPlaylist is available for series detection
    } catch (e) {
      print('Error loading content: $e');
      _deps.setState(() {
        _deps.catalogState.errorMessage =
            'Failed to load content: ${e.toString()}';
      });
    } finally {
      if (_deps.mounted()) {
        _deps.setState(() {
          _deps.catalogState.isLoading = false;
        });
      }
    }
  }

  /// Load Real-Debrid content
  Future<void> loadRealDebridContent() async {
    final rdTorrentId = _deps.playlistItem()['rdTorrentId'] as String?;
    if (rdTorrentId == null) {
      throw Exception('No Real-Debrid torrent ID found');
    }

    final apiKey = await RealDebridStorage.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('No API key configured');
    }

    final info = await DebridService.getTorrentInfo(apiKey, rdTorrentId);
    final allFiles = (info['files'] as List<dynamic>? ?? const []);

    if (allFiles.isEmpty) {
      throw Exception('No files found in torrent');
    }

    // Use existing RDFolderTreeBuilder utility
    _deps.catalogState.rootContent = RDFolderTreeBuilder.buildTree(
      allFiles.cast<Map<String, dynamic>>(),
    );
  }

  /// Load AllDebrid content. Re-adds the magnet by infohash (trusting the
  /// `ready` flag), then builds the tree from its files. The files are kept in
  /// order so each node's [RDFileNode.linkIndex] maps to its locked link.
  Future<void> loadAllDebridContent() async {
    final torrentHash = _deps.playlistItem()['torrent_hash'] as String?;
    if (torrentHash == null || torrentHash.isEmpty) {
      throw Exception('No AllDebrid magnet info found');
    }
    final apiKey = await AllDebridStorage.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('No AllDebrid API key configured');
    }

    final result = await AllDebridService.addMagnetAndResolveFiles(
      apiKey,
      'magnet:?xt=urn:btih:$torrentHash',
    );
    if (result.files.isEmpty) {
      throw Exception('No files found in magnet');
    }

    _deps.catalogState.allDebridFiles = result.files;
    // Map AllDebrid files to RD-style file maps; linkIndex is assigned in this
    // same order by the tree builder, so it indexes back into _allDebridFiles.
    final fileMaps = <Map<String, dynamic>>[];
    for (int i = 0; i < _deps.catalogState.allDebridFiles.length; i++) {
      final f = _deps.catalogState.allDebridFiles[i];
      fileMaps.add({
        'id': i,
        'path': f.path.startsWith('/') ? f.path : '/${f.path}',
        'bytes': f.size,
        'selected': 1,
      });
    }
    _deps.catalogState.rootContent = RDFolderTreeBuilder.buildTree(fileMaps);
  }

  /// Load Torbox content
  Future<void> loadTorboxContent() async {
    final torboxTorrentId = _deps.playlistItem()['torboxTorrentId'] as int?;
    if (torboxTorrentId == null) {
      throw Exception('No Torbox torrent ID found');
    }

    final String? apiKey = await TorboxStorage.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Please set your Torbox API key in Settings');
    }

    final cachedTorrent = await TorboxService.getTorrentById(
      apiKey,
      torboxTorrentId,
    );
    if (cachedTorrent == null) {
      throw Exception('Torrent not found');
    }

    final allFiles = cachedTorrent.files ?? [];
    if (allFiles.isEmpty) {
      throw Exception('No files found in torrent');
    }

    // Use existing TorboxFolderTreeBuilder utility which accepts TorboxFile objects
    _deps.catalogState.rootContent = TorboxFolderTreeBuilder.buildTree(
      allFiles,
    );
  }
}
