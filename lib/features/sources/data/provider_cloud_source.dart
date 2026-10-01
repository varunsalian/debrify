import '../../../models/playback_meta.dart';
import '../../../models/playlist_entry.dart';
import '../../../models/series_source.dart';
import '../../../models/torbox_file.dart';
import '../../../models/torbox_web_download.dart';
import '../../../services/alldebrid_service.dart';
import '../../../services/debrid_service.dart';
import '../../../services/pikpak_api_service.dart';
import '../../../services/premiumize_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/storage_service.dart';
import '../../../services/torbox_service.dart';
import '../../../utils/file_utils.dart';
import '../models/acquired_source.dart';
import 'pikpak_source_acquisition.dart';
import 'pikpak_source_preparation.dart';
import 'source_file_ordering.dart';

/// Refresh a hashless saved cloud source by its stable provider identity.
/// Provider data/playlist preparation stays independent of player presentation.
class ProviderCloudSource {
  const ProviderCloudSource();

  Future<AcquiredSource?> resolve(
    SeriesSource source,
    PlaybackMeta meta, {
    required ProfileSessionOwner owner,
    required bool Function() canContinue,
  }) {
    bool active() =>
        owner == ProfileSessionMemory.captureOwner() && canContinue();
    Future<AcquiredSource?> run() async {
      if (!active()) return null;
      try {
        final result = await _resolve(source, meta, active);
        return active() ? result : null;
      } catch (_) {
        if (!active()) return null;
        rethrow;
      }
    }

    final scope = owner.scope;
    return scope == null
        ? ProfileRuntime.withoutCapturedScope(run)
        : ProfileRuntime.withCapturedScope(scope, run);
  }

  Future<AcquiredSource?> _resolve(
    SeriesSource source,
    PlaybackMeta meta,
    bool Function() active,
  ) async {
    final sourceId = source.debridTorrentId.trim();
    if (!source.isProviderNativeCloud || sourceId.isEmpty) return null;

    switch (source.debridService) {
      case 'rd':
        if (source.cloudSourceKind != SeriesSource.cloudKindWebDownload) {
          return null;
        }
        final apiKey =
            (await StorageService.getApiKey(canContinue: active)) ?? '';
        if (!active()) return null;
        if (apiKey.isEmpty) return null;
        final download = await DebridService.getDownloadById(
          apiKey,
          sourceId,
          canContinue: active,
        );
        if (!active()) return null;
        if (download == null) return null;
        var url = download.download;
        if (download.link.isNotEmpty) {
          try {
            final refreshed = await DebridService.unrestrictLink(
              apiKey,
              download.link,
              canContinue: active,
            );
            if (!active()) return null;
            final refreshedUrl = refreshed['download']?.toString() ?? '';
            if (refreshedUrl.isNotEmpty) url = refreshedUrl;
          } catch (_) {
            // The freshly listed download URL is still a useful fallback when
            // a host temporarily refuses to unrestrict the original link.
          }
        }
        if (url.isEmpty) return null;
        return AcquiredSource(
          title: source.torrentName,
          playUrl: url,
          downloadUrls: [url],
          fileName: download.filename.isNotEmpty
              ? download.filename
              : source.torrentName,
        );

      case 'torbox':
        if (source.cloudSourceKind != SeriesSource.cloudKindWebDownload) {
          return null;
        }
        final apiKey =
            (await StorageService.getTorboxApiKey(canContinue: active)) ?? '';
        if (!active()) return null;
        final webId = int.tryParse(sourceId);
        if (apiKey.isEmpty || webId == null) return null;
        final result = await TorboxService.getWebDownloads(
          apiKey,
          webId: webId,
        );
        if (!active()) return null;
        final downloads = (result['webDownloads'] as List)
            .cast<TorboxWebDownload>();
        if (downloads.isEmpty) return null;
        final download = downloads.firstWhere(
          (candidate) => candidate.id == webId,
          orElse: () => downloads.first,
        );
        final videos = download.files.where((file) {
          if (file.zipped) return false;
          final name = file.shortName.isNotEmpty
              ? file.shortName
              : FileUtils.getFileName(file.name);
          return (file.mimetype?.startsWith('video/') ?? false) ||
              FileUtils.isVideoFile(name);
        }).toList();
        if (videos.isEmpty) return null;

        String displayName(TorboxFile file) => file.shortName.isNotEmpty
            ? file.shortName
            : FileUtils.getFileName(file.name);
        String relativePath(TorboxFile file) =>
            (file.absolutePath?.isNotEmpty ?? false)
            ? file.absolutePath!
            : file.name;

        if (meta.contentType != 'series') {
          final video = videos.reduce((a, b) => a.size >= b.size ? a : b);
          final url = await TorboxService.requestWebDownloadFileLink(
            apiKey: apiKey,
            webId: webId,
            fileId: video.id,
          );
          if (!active()) return null;
          if (url.isEmpty) return null;
          return AcquiredSource(
            title: source.torrentName,
            playUrl: url,
            downloadUrls: [url],
            fileName: displayName(video),
          );
        }

        final (sorted, startIndex) = orderSourceFiles(videos, relativePath);
        final entries = <PlaylistEntry>[
          for (var i = 0; i < sorted.length; i++)
            PlaylistEntry(
              url: '',
              title: relativePath(sorted[i]),
              relativePath: relativePath(sorted[i]),
              provider: 'torbox',
              torboxWebDownloadId: webId,
              torboxFileId: sorted[i].id,
              sizeBytes: sorted[i].size > 0 ? sorted[i].size : null,
            ),
        ];
        final playUrl = await TorboxService.requestWebDownloadFileLink(
          apiKey: apiKey,
          webId: webId,
          fileId: sorted[startIndex].id,
        );
        if (!active()) return null;
        if (playUrl.isEmpty) return null;
        entries[startIndex] = PlaylistEntry(
          url: playUrl,
          title: entries[startIndex].title,
          relativePath: entries[startIndex].relativePath,
          provider: entries[startIndex].provider,
          torboxWebDownloadId: webId,
          torboxFileId: sorted[startIndex].id,
          sizeBytes: entries[startIndex].sizeBytes,
        );
        return AcquiredSource(
          title: source.torrentName,
          playUrl: playUrl,
          downloadUrls: [playUrl],
          playlist: entries.length > 1 ? entries : null,
          startIndex: startIndex,
          fileName: entries.length == 1 ? entries.first.title : null,
        );

      case 'alldebrid':
        if (source.cloudSourceKind != SeriesSource.cloudKindWebDownload) {
          return null;
        }
        final apiKey =
            (await StorageService.getAllDebridApiKey(canContinue: active)) ??
            '';
        if (!active()) return null;
        if (apiKey.isEmpty) return null;
        final links = await AllDebridService.listSavedLinks(apiKey);
        if (!active()) return null;
        final matching = links.where(
          (link) => SeriesSource.opaqueCloudReference(link.link) == sourceId,
        );
        if (matching.isEmpty) return null;
        final link = matching.first;
        final url = await AllDebridService.unlockLink(
          apiKey,
          link.link,
          canContinue: active,
        );
        if (!active()) return null;
        if (url.isEmpty) return null;
        return AcquiredSource(
          title: source.torrentName,
          playUrl: url,
          downloadUrls: [url],
          fileName: link.fileName,
        );

      case 'premiumize':
        final apiKey =
            (await StorageService.getPremiumizeApiKey(canContinue: active)) ??
            '';
        if (!active()) return null;
        if (apiKey.isEmpty) return null;
        if (source.cloudSourceKind == SeriesSource.cloudKindFile) {
          final file = await PremiumizeService.resolveItemById(
            apiKey,
            sourceId,
          );
          if (!active()) return null;
          if (file == null || file.link.isEmpty) return null;
          return AcquiredSource(
            title: source.torrentName,
            playUrl: file.link,
            downloadUrls: [file.link],
            fileName: file.path.isNotEmpty ? file.path : source.torrentName,
          );
        }

        final all = await PremiumizeService.listFolderRecursive(
          apiKey,
          sourceId,
          canContinue: active,
        );
        if (!active()) return null;
        final videos = all.where((f) => f.isVideo).toList();
        if (videos.isEmpty) return null;
        if (meta.contentType != 'series') {
          final video = videos.reduce((a, b) => a.size >= b.size ? a : b);
          var url = video.playableUrl ?? '';
          if (url.isEmpty) {
            final resolved = await PremiumizeService.resolveItemById(
              apiKey,
              video.id,
            );
            if (!active()) return null;
            url = resolved?.link ?? '';
          }
          if (url.isEmpty) return null;
          return AcquiredSource(
            title: source.torrentName,
            playUrl: url,
            downloadUrls: [url],
            fileName: video.relativePath ?? video.name,
          );
        }
        final (sorted, startIndex) = orderSourceFiles(
          videos,
          (f) => f.relativePath ?? f.name,
        );
        final entries = <PlaylistEntry>[
          for (var i = 0; i < sorted.length; i++)
            PlaylistEntry(
              url: i == startIndex ? (sorted[i].playableUrl ?? '') : '',
              title: sorted[i].relativePath ?? sorted[i].name,
              relativePath: sorted[i].relativePath ?? sorted[i].name,
              provider: 'premiumize',
              premiumizeItemId: sorted[i].id,
              sizeBytes: sorted[i].size > 0 ? sorted[i].size : null,
            ),
        ];
        var playUrl = entries[startIndex].url;
        if (playUrl.isEmpty) {
          final resolved = await PremiumizeService.resolveItemById(
            apiKey,
            entries[startIndex].premiumizeItemId!,
          );
          if (!active()) return null;
          playUrl = resolved?.link ?? '';
        }
        if (playUrl.isEmpty) return null;
        return AcquiredSource(
          title: source.torrentName,
          playUrl: playUrl,
          downloadUrls: [playUrl],
          playlist: entries.length > 1 ? entries : null,
          startIndex: startIndex,
          fileName: entries.length == 1 ? entries.first.title : null,
        );

      case 'pikpak':
        final pikpak = PikPakApiService.instance;
        if (source.cloudSourceKind == SeriesSource.cloudKindFile) {
          final data = await pikpak.getFileDetails(
            sourceId,
            canContinue: active,
          );
          if (!active()) return null;
          if (data['phase'] != 'PHASE_TYPE_COMPLETE') return null;
          final url = pikpak.getStreamingUrl(data);
          if (url == null || url.isEmpty) return null;
          final name = (data['name'] ?? source.torrentName).toString();
          return AcquiredSource(
            title: source.torrentName,
            playUrl: url,
            downloadUrls: [url],
            fileName: name,
            pikpakFileId: sourceId,
            pikpakVideoFileId: sourceId,
          );
        }

        final all = await pikpak.listFilesRecursive(
          folderId: sourceId,
          includePaths: true,
          canContinue: active,
        );
        if (!active()) return null;
        final videos = all.where((file) {
          final name = file['name']?.toString() ?? '';
          final mime = file['mime_type']?.toString() ?? '';
          return mime.startsWith('video/') || FileUtils.isVideoFile(name);
        }).toList();
        if (videos.isEmpty) return null;
        if (meta.contentType != 'series') {
          int sizeOf(Map<String, dynamic> file) =>
              int.tryParse(file['size']?.toString() ?? '') ?? 0;
          final video = videos.reduce((a, b) => sizeOf(a) >= sizeOf(b) ? a : b);
          final videoId = video['id']?.toString() ?? '';
          if (videoId.isEmpty) return null;
          final data = await pikpak.getFileDetails(
            videoId,
            canContinue: active,
          );
          if (!active()) return null;
          if (data['phase'] != 'PHASE_TYPE_COMPLETE') return null;
          final url = pikpak.getStreamingUrl(data);
          if (url == null || url.isEmpty) return null;
          return AcquiredSource(
            title: source.torrentName,
            playUrl: url,
            downloadUrls: [url],
            fileName:
                video['_fullPath']?.toString() ??
                video['name']?.toString() ??
                source.torrentName,
            pikpakFileId: sourceId,
            pikpakVideoFileId: videoId,
          );
        }
        final playlist = await buildPikPakSourcePlaylist(
          source.torrentName,
          videos.map(pikPakSourceVideoFromJson).toList(),
          pikpak,
          canContinue: active,
        );
        if (!active()) return null;
        if (playlist == null || playlist.isEmpty) return null;
        var startIndex = playlist.indexWhere((e) => e.url.isNotEmpty);
        if (startIndex < 0) startIndex = 0;
        final playUrl = playlist[startIndex].url;
        if (playUrl.isEmpty) return null;
        return AcquiredSource(
          title: source.torrentName,
          playUrl: playUrl,
          downloadUrls: [playUrl],
          playlist: playlist.length > 1 ? playlist : null,
          startIndex: startIndex,
          fileName: playlist.length == 1 ? playlist.first.title : null,
          pikpakFileId: sourceId,
          pikpakVideoFileId: playlist.length == 1
              ? playlist.first.pikpakFileId
              : null,
        );
    }
    return null;
  }
}
