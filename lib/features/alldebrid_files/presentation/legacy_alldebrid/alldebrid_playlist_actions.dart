import 'dart:async';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation_state.dart';
import 'package:debrify/models/alldebrid_file.dart';
import 'package:debrify/models/alldebrid_magnet.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/utils/file_utils.dart';

typedef AllDebridPlaylistActionsDeps = ({
  AllDebridLibraryState libraryState,
  AllDebridNavigationState navigationState,
  bool Function() mounted,
  void Function() dismissLoading,
  bool Function(AllDebridFile f) looksLikeVideo,
  void Function(String message) showLoading,
  void Function(String message, {bool isError}) snack,
});

class AllDebridPlaylistActions {
  final AllDebridPlaylistActionsDeps _deps;
  AllDebridPlaylistActions(this._deps);
  AllDebridLibraryState get _library => _deps.libraryState;
  AllDebridNavigationState get _navigation => _deps.navigationState;

  // ── Add to playlist ─────────────────────────────────────────────────────

  /// Saves a magnet to the playlist (RD-manner: keyed by infohash). Single
  /// video → 'single' with its locked link; multiple → 'collection' re-resolved
  /// by hash at play time.
  Future<void> addMagnetToPlaylist(AllDebridMagnet magnet) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    if (magnet.hash.isEmpty) {
      _deps.snack('This magnet has no infohash to save.', isError: true);
      return;
    }
    List<AllDebridFile> files = _navigation.currentFiles;
    if (_navigation.currentMagnet?.id != magnet.id || files.isEmpty) {
      _deps.showLoading('Scanning magnet…');
      try {
        files = await AllDebridService.getMagnetFiles(apiKey, magnet.id);
      } catch (e) {
        _deps.dismissLoading();
        _deps.snack('Failed to scan magnet: $e', isError: true);
        return;
      }
      _deps.dismissLoading();
    }
    final videos = files.where(_deps.looksLikeVideo).toList();
    if (videos.isEmpty) {
      _deps.snack('No video files to add.', isError: true);
      return;
    }
    bool added;
    if (videos.length == 1) {
      added = await PlaylistStorage.addPlaylistItemRaw({
        'provider': 'alldebrid',
        'title': FileUtils.cleanPlaylistTitle(magnet.name),
        'kind': 'single',
        'torrent_hash': magnet.hash,
        'allDebridLink': videos.first.link,
        'sizeBytes': videos.first.size,
      });
    } else {
      added = await PlaylistStorage.addPlaylistItemRaw({
        'provider': 'alldebrid',
        'title': FileUtils.cleanPlaylistTitle(magnet.name),
        'kind': 'collection',
        'torrent_hash': magnet.hash,
        'count': videos.length,
      });
    }
    if (!_deps.mounted()) return;
    _deps.snack(
      added ? 'Added to playlist' : 'Already in playlist',
      isError: !added,
    );
  }
}
