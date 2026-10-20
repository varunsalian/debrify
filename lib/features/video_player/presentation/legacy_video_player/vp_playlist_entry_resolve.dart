import 'dart:async';

import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/torbox_service.dart';

abstract interface class VpPlaylistEntryResolveHost {
  List<PlaylistEntry>? get activePlaylist;
}

class VpPlaylistEntryResolve {
  VpPlaylistEntryResolve(this._host);
  final VpPlaylistEntryResolveHost _host;

  Future<String> resolvePlaylistEntryUrl(int index) async {
    if (_host.activePlaylist == null ||
        index < 0 ||
        index >= _host.activePlaylist!.length) {
      return '';
    }

    final entry = _host.activePlaylist![index];

    if (entry.url.isNotEmpty) {
      return entry.url;
    }

    final provider = entry.provider?.toLowerCase();
    final hasTorboxMetadata =
        entry.torboxTorrentId != null && entry.torboxFileId != null;
    final hasTorboxWebDownloadMetadata =
        entry.torboxWebDownloadId != null && entry.torboxFileId != null;

    if (provider == 'torbox' ||
        hasTorboxMetadata ||
        hasTorboxWebDownloadMetadata) {
      final torrentId = entry.torboxTorrentId;
      final webDownloadId = entry.torboxWebDownloadId;
      final fileId = entry.torboxFileId;
      if (fileId == null || (torrentId == null && webDownloadId == null)) {
        throw Exception('Torbox file metadata missing');
      }
      final apiKey = await TorboxStorage.getTorboxApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Torbox API key');
      }
      try {
        String url;
        if (webDownloadId != null) {
          // Web download - use web download API
          url = await TorboxService.requestWebDownloadFileLink(
            apiKey: apiKey,
            webId: webDownloadId,
            fileId: fileId,
          );
        } else {
          // Torrent - use torrent API
          url = await TorboxService.requestFileDownloadLink(
            apiKey: apiKey,
            torrentId: torrentId!,
            fileId: fileId,
          );
        }
        if (url.isEmpty) {
          throw Exception('Torbox returned an empty stream URL');
        }
        return url;
      } catch (e) {
        throw Exception('Torbox link failed: $e');
      }
    }

    // PikPak lazy resolution
    final hasPikPakMetadata = entry.pikpakFileId != null;
    if (provider == 'pikpak' || hasPikPakMetadata) {
      final fileId = entry.pikpakFileId;
      if (fileId == null) {
        throw Exception('PikPak file metadata missing');
      }
      try {
        final pikpak = PikPakApiService.instance;
        final fileData = await pikpak.getFileDetails(fileId);
        final url = pikpak.getStreamingUrl(fileData);
        if (url == null || url.isEmpty) {
          throw Exception('PikPak returned an empty stream URL');
        }
        return url;
      } catch (e) {
        throw Exception('PikPak link failed: $e');
      }
    }

    // Premiumize cloud-browser lazy resolution: re-fetch a fresh direct link by
    // cloud item id (items saved from the cloud browser have no infohash).
    if (entry.premiumizeItemId != null && entry.premiumizeItemId!.isNotEmpty) {
      final apiKey = await PremiumizeStorage.getPremiumizeApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Premiumize API key');
      }
      try {
        final file = await PremiumizeService.resolveItemById(
          apiKey,
          entry.premiumizeItemId!,
        );
        if (file == null || file.link.isEmpty) {
          throw Exception('File not found in Premiumize cloud');
        }
        return file.link;
      } catch (e) {
        throw Exception('Premiumize link failed: $e');
      }
    }

    // Premiumize lazy resolution: re-fetch direct links by infohash and match
    // the file by its stored path (Premiumize direct links eventually expire).
    final hasPremiumizeMetadata =
        entry.premiumizeHash != null && entry.premiumizePath != null;
    if (provider == 'premiumize' || hasPremiumizeMetadata) {
      final hash = entry.premiumizeHash;
      final path = entry.premiumizePath;
      if (hash == null || hash.isEmpty || path == null || path.isEmpty) {
        throw Exception('Premiumize file metadata missing');
      }
      final apiKey = await PremiumizeStorage.getPremiumizeApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Premiumize API key');
      }
      try {
        final files = await PremiumizeService.resolveFilesByHash(apiKey, hash);
        final match = files.firstWhere(
          (f) => f.path == path,
          orElse: () => throw Exception('File not found in Premiumize cloud'),
        );
        if (match.link.isEmpty) {
          throw Exception('Premiumize returned an empty stream URL');
        }
        return match.link;
      } catch (e) {
        throw Exception('Premiumize link failed: $e');
      }
    }

    if (entry.restrictedLink != null) {
      final apiKey = await RealDebridStorage.getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Real Debrid API key');
      }
      try {
        final unrestrictResult = await DebridService.unrestrictLink(
          apiKey,
          entry.restrictedLink!,
        );
        final url = unrestrictResult['download']?.toString() ?? '';
        if (url.isEmpty) {
          throw Exception('Real Debrid returned an empty stream URL');
        }
        return url;
      } catch (e) {
        throw Exception('Real Debrid link failed: $e');
      }
    }

    // AllDebrid lazy resolution: unlock the stored locked link on demand
    // (mirrors Real-Debrid's restrictedLink → unrestrict). The locked link is
    // stable; only the unlocked CDN URL expires, so this is also more robust
    // than resolving every episode up front.
    if (provider == 'alldebrid' ||
        (entry.allDebridLink != null && entry.allDebridLink!.isNotEmpty)) {
      final lockedLink = entry.allDebridLink;
      if (lockedLink == null || lockedLink.isEmpty) {
        throw Exception('AllDebrid link metadata missing');
      }
      final apiKey = await AllDebridStorage.getAllDebridApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing AllDebrid API key');
      }
      try {
        final url = await AllDebridService.unlockLink(apiKey, lockedLink);
        if (url.isEmpty) {
          throw Exception('AllDebrid returned an empty stream URL');
        }
        return url;
      } catch (e) {
        throw Exception('AllDebrid link failed: $e');
      }
    }

    throw Exception('No URL metadata available for this entry');
  }
}
