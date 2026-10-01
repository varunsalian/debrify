import 'package:debrify/services/storage/playlist_storage.dart';
import '../../../models/playback_meta.dart';
import '../../../models/torrent.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../utils/file_utils.dart';
import '../models/acquired_source.dart';

/// Provider-native playlist persistence retains the acquisition's profile owner.
class SourcePlaylist {
  const SourcePlaylist({required this.owner, required this.canContinue});
  final ProfileSessionOwner owner;
  final bool Function() canContinue;
  bool get isCurrent =>
      owner == ProfileSessionMemory.captureOwner() && canContinue();

  Future<bool> add(
    AcquiredSource source,
    Torrent torrent,
    String provider, {
    PlaybackMeta? meta,
  }) async {
    if (!isCurrent) return false;
    Future<bool> save() => PlaylistStorage.addPlaylistItemRaw(
      describe(source, torrent, provider, meta: meta),
      canContinue: () => isCurrent,
    );
    final scope = owner.scope;
    return scope == null
        ? ProfileRuntime.withoutCapturedScope(save)
        : ProfileRuntime.withCapturedScope(scope, save);
  }

  static Map<String, dynamic> describe(
    AcquiredSource r,
    Torrent torrent,
    String provider, {
    PlaybackMeta? meta,
  }) {
    final isPack = r.hasPlaylist;
    final rawTitle = (!isPack && r.fileName != null)
        ? r.fileName!
        : torrent.displayTitle;
    // Base fields shared by every provider. NOTE: no 'url' is stored — the
    // playlist player RE-RESOLVES a fresh link from the provider-native ids
    // below, so saved items keep working after the debrid direct link expires
    // (parity with the old per-provider playlist schema).
    final item = <String, dynamic>{
      'provider': provider == 'debrid' ? 'realdebrid' : provider,
      'title': FileUtils.cleanPlaylistTitle(rawTitle),
      'kind': isPack ? 'collection' : 'single',
      'torrent_hash': torrent.infohash,
      if (isPack) 'count': r.playlist!.length,
      if (torrent.sizeBytes > 0) 'sizeBytes': torrent.sizeBytes,
      // Catalog identity so the playlist shows poster art + links back (Home).
      if (meta?.imdbId != null && meta!.imdbId!.isNotEmpty)
        'imdbId': meta.imdbId,
      if (meta?.contentType != null) 'contentType': meta!.contentType,
      if (meta?.posterUrl != null && meta!.posterUrl!.isNotEmpty)
        'posterUrl': meta.posterUrl,
    };
    // Provider-native identifiers for re-resolution. For packs, per-file ids are
    // pulled from the resolved playlist entries; for single files they ride on
    // [AcquiredSource].
    switch (provider) {
      case 'debrid': // Real-Debrid
        if (r.rdTorrentId != null) item['rdTorrentId'] = r.rdTorrentId;
        if (!isPack) {
          item['url'] = ''; // force re-resolution from restrictedLink
          if (r.restrictedLink != null) {
            item['restrictedLink'] = r.restrictedLink;
          }
        }
        break;
      case 'torbox':
        item['torboxTorrentId'] = r.torboxTorrentId;
        if (isPack) {
          item['torboxFileIds'] = [
            for (final e in r.playlist!)
              if (e.torboxFileId != null) e.torboxFileId,
          ];
        } else if (r.torboxFileId != null) {
          item['torboxFileId'] = r.torboxFileId;
        }
        break;
      case 'premiumize':
        // Collections re-resolve from torrent_hash; singles from the file path.
        if (!isPack && r.premiumizePath != null) {
          item['premiumizePath'] = r.premiumizePath;
        }
        break;
      case 'alldebrid':
        // Collections re-resolve from torrent_hash; singles from the locked link.
        if (!isPack && r.allDebridLink != null) {
          item['allDebridLink'] = r.allDebridLink;
        }
        break;
      case 'pikpak':
        if (isPack) {
          // Pack: folder id + per-file video ids (player collection path).
          item['pikpakFileId'] = r.pikpakFileId;
          item['pikpakFileIds'] = [
            for (final e in r.playlist!)
              if (e.pikpakFileId != null) e.pikpakFileId,
          ];
        } else {
          // Single: the playable VIDEO-file id, NOT the folder id — else the
          // player can't get a streaming URL and the item won't play.
          item['pikpakFileId'] = r.pikpakVideoFileId ?? r.pikpakFileId;
        }
        break;
    }
    return item;
  }
}
