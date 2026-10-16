import 'package:flutter/foundation.dart';
import 'package:debrify/features/video_player/application/vp_filename_hash.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/playlist_entry.dart';

abstract interface class VpResumeKeysHost {
  List<PlaylistEntry>? get activePlaylist;
  int get currentIndex;
  int get currentIptvIndex;
  int? get effectiveContentEpisode;
  String? get effectiveContentImdbId;
  int? get effectiveContentSeason;
  List<IptvChannel>? get effectiveIptvChannels;
  String get title;
  String get videoUrl;
}

class VpResumeKeys {
  VpResumeKeys(this._host);
  final VpResumeKeysHost _host;

  String get resumeKey {
    final customKey = CustomSeriesIdentity.resumeBookmarkKey(
      _host.effectiveContentImdbId,
      _host.effectiveContentSeason,
      _host.effectiveContentEpisode,
    );
    if (customKey != null) return customKey;
    if (_host.activePlaylist != null &&
        _host.activePlaylist!.isNotEmpty &&
        _host.currentIndex >= 0 &&
        _host.currentIndex < _host.activePlaylist!.length) {
      final entry = _host.activePlaylist![_host.currentIndex];

      // Check for Torbox-specific key
      final torboxKey = torboxResumeKeyForEntry(entry);
      if (torboxKey != null) {
        debugPrint(
          'ResumeKey: using torbox key $torboxKey for index ${_host.currentIndex}',
        );
        return torboxKey;
      }

      // Check for PikPak-specific key
      final pikpakKey = pikpakResumeKeyForEntry(entry);
      if (pikpakKey != null) {
        debugPrint(
          'ResumeKey: using pikpak key $pikpakKey for index ${_host.currentIndex}',
        );
        return pikpakKey;
      }
    }

    // Use playlist-specific resume ID for other items
    if (_host.activePlaylist != null &&
        _host.activePlaylist!.isNotEmpty &&
        _host.currentIndex >= 0 &&
        _host.currentIndex < _host.activePlaylist!.length) {
      final id = resumeIdForEntry(_host.activePlaylist![_host.currentIndex]);
      debugPrint(
        'ResumeKey: using playlist entry id $id for index ${_host.currentIndex}',
      );
      return id;
    }

    // IPTV launches carry no playlist, so the fallback below would key every
    // channel in the session to the URL the player was OPENED with — zap to
    // another channel and its position would be filed under the first one's
    // name. Key on the channel actually playing instead. (Identical to the
    // fallback until the user zaps, so existing resume points still resolve.)
    final iptvChannels = _host.effectiveIptvChannels;
    if (iptvChannels != null &&
        _host.currentIptvIndex >= 0 &&
        _host.currentIptvIndex < iptvChannels.length) {
      return iptvChannels[_host.currentIptvIndex].url;
    }

    // Fallback to videoUrl for single items
    // Note: This is the expected path for Debrify TV mode
    return _host.videoUrl;
  }

  String? torboxResumeKeyForEntry(PlaylistEntry entry) {
    final provider = entry.provider?.toLowerCase();
    if (provider == 'torbox') {
      final torrentId = entry.torboxTorrentId;
      final webDownloadId = entry.torboxWebDownloadId;
      final fileId = entry.torboxFileId;
      if (webDownloadId != null && fileId != null) {
        debugPrint(
          'ResumeKey: torbox web download detected web=$webDownloadId file=$fileId',
        );
        return 'torbox_web_${webDownloadId}_$fileId';
      }
      if (torrentId != null && fileId != null) {
        debugPrint(
          'ResumeKey: torbox entry detected torrent=$torrentId file=$fileId',
        );
        return 'torbox_${torrentId}_$fileId';
      }
      debugPrint(
        'ResumeKey: torbox entry missing IDs torrent=$torrentId web=$webDownloadId file=$fileId',
      );
    }
    return null;
  }

  String? pikpakResumeKeyForEntry(PlaylistEntry entry) {
    final provider = entry.provider?.toLowerCase();
    if (provider == 'pikpak') {
      final fileId = entry.pikpakFileId;
      if (fileId != null && fileId.isNotEmpty) {
        debugPrint('ResumeKey: pikpak entry detected fileId=$fileId');
        return 'pikpak_$fileId';
      }
      debugPrint('ResumeKey: pikpak entry missing fileId');
    }
    return null;
  }

  String resumeIdForEntry(PlaylistEntry entry) {
    // Check for Torbox-specific key
    final torboxKey = torboxResumeKeyForEntry(entry);
    if (torboxKey != null) {
      return torboxKey;
    }
    // Check for PikPak-specific key
    final pikpakKey = pikpakResumeKeyForEntry(entry);
    if (pikpakKey != null) {
      return pikpakKey;
    }
    // Fallback to filename hash
    final name = entry.title.isNotEmpty ? entry.title : _host.title;
    return vpFilenameHash(name);
  }
}
