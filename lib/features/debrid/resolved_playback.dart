import '../../core/playback/playlist_entry.dart';

/// What a provider produced for one added torrent: something to play, links to
/// download, and the provider-native ids needed to re-resolve it later.
class ResolvedPlayback {
  final String title;
  final String? playUrl;
  final List<String> downloadUrls;

  /// Opens the provider's own file view on this entry, when it has one.
  final void Function()? openInTab;

  /// Multi-file playlist (season packs); the launcher lazily resolves each
  /// entry's URL from its provider metadata (torboxFileId / allDebridLink /
  /// restrictedLink / premiumizePath / pikpakFileId). [startIndex] is the
  /// first-episode entry to begin playback at.
  final List<PlaylistEntry>? playlist;
  final int startIndex;

  /// The single resolved file's name (with extension) for download naming.
  final String? fileName;

  /// RD only: an unextracted RAR archive (multiple files, one link). The
  /// provider "open" view isn't useful for these, so it's disabled.
  final bool isRarArchive;

  /// TorBox only: the torrent id, for the "Copy Download Link (Zip)" action.
  final int? torboxTorrentId;

  /// RD only: the account entry this add created (RD's addMagnet always makes
  /// a fresh entry), so a rejected bound-source attempt can delete it again.
  final String? rdTorrentId;

  /// PikPak only: the drive entry (file/folder) this add created (PikPak's
  /// addOfflineDownload always makes a fresh entry), so a rejected
  /// bound-source attempt can delete it again.
  final String? pikpakFileId;

  // Single-file provider-native identifiers, captured so an "Add to playlist"
  // item can be RE-RESOLVED after the direct URL expires (the playlist player
  // re-derives a fresh link from these) — parity with the old per-provider
  // playlist schema. Only the field for the resolved provider is set.
  final String? restrictedLink; // RD: raw restricted link to re-unrestrict
  final int? torboxFileId; // TorBox: file id to re-request a download link
  final String? premiumizePath; // Premiumize: file path (matched on re-resolve)
  final String? allDebridLink; // AllDebrid: locked link to re-unlock
  // PikPak: the playable VIDEO-file id for a single (distinct from
  // [pikpakFileId], which is the offline-download FOLDER id used for
  // bound-source deletes). A playlist item must store the video-file id or the
  // player can't get a streaming URL from a folder.
  final String? pikpakVideoFileId;

  const ResolvedPlayback({
    required this.title,
    this.playUrl,
    this.downloadUrls = const [],
    this.openInTab,
    this.playlist,
    this.startIndex = 0,
    this.fileName,
    this.isRarArchive = false,
    this.torboxTorrentId,
    this.rdTorrentId,
    this.pikpakFileId,
    this.restrictedLink,
    this.torboxFileId,
    this.premiumizePath,
    this.allDebridLink,
    this.pikpakVideoFileId,
  });

  bool get hasPlaylist => playlist != null && playlist!.length > 1;
}
