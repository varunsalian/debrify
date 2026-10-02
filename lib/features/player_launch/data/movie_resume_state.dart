import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/services/local_playback_resume_resolver.dart';

final class MovieResumeState {
  /// Generate a resume key for a playlist entry.
  /// Used to pre-populate playback state (e.g., from Trakt progress).
  static String resumeIdForEntry(
    PlaylistEntry entry, {
    String fallbackTitle = '',
  }) {
    final provider = entry.provider?.toLowerCase();
    // Torbox
    if (provider == 'torbox') {
      final torrentId = entry.torboxTorrentId;
      final webDownloadId = entry.torboxWebDownloadId;
      final fileId = entry.torboxFileId;
      if (webDownloadId != null && fileId != null) {
        return 'torbox_web_${webDownloadId}_$fileId';
      }
      if (torrentId != null && fileId != null) {
        return 'torbox_${torrentId}_$fileId';
      }
    }
    // PikPak
    if (provider == 'pikpak') {
      final fileId = entry.pikpakFileId;
      if (fileId != null && fileId.isNotEmpty) {
        return 'pikpak_$fileId';
      }
    }
    // Fallback: filename hash
    final name = entry.title.isNotEmpty ? entry.title : fallbackTitle;
    final nameWithoutExt = name.replaceAll(RegExp(r'\.[^.]*$'), '');
    return nameWithoutExt.hashCode.toString();
  }

  /// Local resume record for a NON-series entry.
  ///
  /// [resumeIdForEntry] keys movies by release filename (or by debrid file id),
  /// so watching via one source and relaunching via another — Quick Play
  /// auto-picking a different torrent, an unpinned binding, a startup failover
  /// landing on candidate 3 — misses the record and restarts from zero. The
  /// Flutter player already recovers from that by scanning for the IMDb id
  /// (see `_getEnhancedPlaybackState`); this is the native-TV counterpart, so
  /// both players resolve movie resume the same way.
  ///
  /// Generic playback remains exact-source-first. Catalog playback reverses
  /// that precedence so the newest record for the stable IMDb id wins even
  /// when the selected source has an older bookmark of its own.
  static Future<Map<String, dynamic>?> readMovieResumeState({
    required PlaylistEntry entry,
    required String? imdbId,
    String fallbackTitle = '',
    PlaybackResumePolicy policy = PlaybackResumePolicy.sourceSpecific,
  }) async {
    // A canonical record's duration belongs to the source that wrote it and
    // may differ for another cut. Both players validate the absolute position
    // against the live duration before seeking, so retain the existing ms-based
    // behavior rather than guessing a percentage here.
    return LocalPlaybackResumeResolver.movie(
      resumeId: MovieResumeState.resumeIdForEntry(entry, fallbackTitle: fallbackTitle),
      imdbId: imdbId,
      policy: policy,
    );
  }
}
