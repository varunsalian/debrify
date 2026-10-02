import 'package:debrify/features/player_launch/data/stream_redirect_resolver.dart';
import 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:debrify/services/profiles/profile_playback_preparation.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/torbox_service.dart';

final class EntryUrlResolver {
  static Future<String> resolveEntryUrl(
    PlaylistEntry entry,
    VideoPlayerLaunchArgs args, {
    bool Function()? canContinue,
  }) async {
    void checkCurrent() {
      if (canContinue?.call() == false) {
        throw const PlaybackPreparationRetired();
      }
    }

    checkCurrent();
    if (entry.url.isNotEmpty) {
      // Keep protected URLs attached to their declared headers and origin.
      // The player handles redirects; the legacy URL-only resolver cannot.
      if ((entry.httpHeaders ?? args.httpHeaders)?.isNotEmpty == true) {
        return entry.url;
      }
      // For direct stream URLs, resolve redirects to get final URL
      // (needed for HLS streams behind short URL redirects like USATV)
      return await StreamRedirectResolver.resolveRedirectUrl(entry.url, canContinue: canContinue);
    }

    final provider = entry.provider?.toLowerCase();
    final hasTorboxMetadata = entry.torboxTorrentId != null && entry.torboxFileId != null;
    final hasTorboxWebDownloadMetadata =
        entry.torboxWebDownloadId != null && entry.torboxFileId != null;

    if (provider == 'torbox' || hasTorboxMetadata || hasTorboxWebDownloadMetadata) {
      final torrentId = entry.torboxTorrentId;
      final webDownloadId = entry.torboxWebDownloadId;
      final fileId = entry.torboxFileId;
      if (fileId == null || (torrentId == null && webDownloadId == null)) {
        throw Exception('Torbox file metadata missing');
      }
      final apiKey = await TorboxStorage.getTorboxApiKey(
        canContinue: canContinue,
      );
      checkCurrent();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Torbox API key');
      }
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
          canContinue: canContinue,
        );
      }
      checkCurrent();
      if (url.isEmpty) {
        throw Exception('Torbox returned an empty stream URL');
      }
      return url;
    }

    // PikPak lazy resolution
    final hasPikPakMetadata = entry.pikpakFileId != null;
    if (provider == 'pikpak' || hasPikPakMetadata) {
      final fileId = entry.pikpakFileId;
      if (fileId == null) {
        throw Exception('PikPak file metadata missing');
      }
      final pikpak = PikPakApiService.instance;
      final fileData = await pikpak.getFileDetails(
        fileId,
        canContinue: canContinue,
      );
      checkCurrent();
      final url = pikpak.getStreamingUrl(fileData);
      if (url == null || url.isEmpty) {
        throw Exception('PikPak returned an empty stream URL');
      }
      return url;
    }

    // Premiumize cloud-browser lazy resolution: re-fetch a fresh direct link by
    // cloud item id (items saved from the cloud browser have no infohash).
    if (entry.premiumizeItemId != null && entry.premiumizeItemId!.isNotEmpty) {
      final apiKey = await PremiumizeStorage.getPremiumizeApiKey(
        canContinue: canContinue,
      );
      checkCurrent();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Premiumize API key');
      }
      final file = await PremiumizeService.resolveItemById(
        apiKey,
        entry.premiumizeItemId!,
      );
      checkCurrent();
      if (file == null || file.link.isEmpty) {
        throw Exception('File not found in Premiumize cloud');
      }
      return file.link;
    }

    // Premiumize lazy resolution: re-fetch direct links by infohash and match
    // the file by its stored path (Premiumize direct links eventually expire).
    final hasPremiumizeMetadata = entry.premiumizeHash != null && entry.premiumizePath != null;
    if (provider == 'premiumize' || hasPremiumizeMetadata) {
      final hash = entry.premiumizeHash;
      final path = entry.premiumizePath;
      if (hash != null && hash.isNotEmpty && path != null && path.isNotEmpty) {
        final apiKey = await PremiumizeStorage.getPremiumizeApiKey(
          canContinue: canContinue,
        );
        checkCurrent();
        if (apiKey == null || apiKey.isEmpty) {
          throw Exception('Missing Premiumize API key');
        }
        final files = await PremiumizeService.resolveFilesByHash(apiKey, hash);
        checkCurrent();
        final match = files.firstWhere(
          (f) => f.path == path,
          orElse: () => throw Exception('File not found in Premiumize cloud'),
        );
        if (match.link.isEmpty) {
          throw Exception('Premiumize returned an empty stream URL');
        }
        return match.link;
      }
    }

    if (entry.restrictedLink != null && entry.restrictedLink!.isNotEmpty) {
      final apiKey = await RealDebridStorage.getApiKey(canContinue: canContinue);
      checkCurrent();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Real Debrid API key');
      }
      final unrestrictResult = await DebridService.unrestrictLink(
        apiKey,
        entry.restrictedLink!,
        canContinue: canContinue,
      );
      checkCurrent();
      final url = unrestrictResult['download']?.toString() ?? '';
      checkCurrent();
      if (url.isEmpty) {
        throw Exception('Real Debrid returned an empty stream URL');
      }
      return url;
    }

    // AllDebrid lazy resolution: unlock the stored locked link on demand.
    if (provider == 'alldebrid' ||
        (entry.allDebridLink != null && entry.allDebridLink!.isNotEmpty)) {
      final lockedLink = entry.allDebridLink;
      if (lockedLink == null || lockedLink.isEmpty) {
        throw Exception('AllDebrid link metadata missing');
      }
      final apiKey = await AllDebridStorage.getAllDebridApiKey(
        canContinue: canContinue,
      );
      checkCurrent();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing AllDebrid API key');
      }
      final url = await AllDebridService.unlockLink(
        apiKey,
        lockedLink,
        canContinue: canContinue,
      );
      checkCurrent();
      if (url.isEmpty) {
        throw Exception('AllDebrid returned an empty stream URL');
      }
      return url;
    }

    if (args.videoUrl.isNotEmpty) {
      return args.videoUrl;
    }

    throw Exception('No URL metadata available for this entry');
  }
}
