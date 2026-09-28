import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../models/alldebrid_file.dart';
import '../../../models/playlist_entry.dart';
import '../../../models/premiumize_file.dart';
import '../../../models/rd_torrent.dart';
import '../../../models/torbox_file.dart';
import '../../../models/torrent.dart';
import '../../../services/alldebrid_service.dart';
import '../../../services/debrid_service.dart';
import '../../../services/premiumize_service.dart';
import '../../../services/storage_service.dart';
import '../../../services/torbox_service.dart';
import '../../../utils/file_utils.dart';
import '../../../utils/rd_folder_tree_builder.dart';
import '../../../utils/series_parser.dart';
import '../models/acquired_source.dart';
import 'pikpak_source_acquisition.dart';
import 'source_file_ordering.dart';

/// Shared provider acquisition. UI callbacks are constructed by presentation.
class SourceAcquisition {
  const SourceAcquisition();

  Future<AcquiredSource> acquire(
    String provider,
    String magnet,
    Torrent torrent, {
    bool Function()? canContinue,
    ProfileSessionOwner? owner,
  }) {
    if (owner == null) {
      return _acquire(provider, magnet, torrent, canContinue: canContinue);
    }
    bool current() =>
        owner == ProfileSessionMemory.captureOwner() &&
        (canContinue?.call() ?? true);
    Future<AcquiredSource> run() =>
        _acquire(provider, magnet, torrent, canContinue: current);
    final scope = owner.scope;
    return scope == null
        ? ProfileRuntime.withoutCapturedScope(run)
        : ProfileRuntime.withCapturedScope(scope, run);
  }

  Future<AcquiredSource> _acquire(
    String provider,
    String magnet,
    Torrent torrent, {
    bool Function()? canContinue,
  }) async {
    void checkCurrent() {
      if (canContinue?.call() == false) {
        throw StateError('Source acquisition belongs to a retired action');
      }
    }

    checkCurrent();
    final title = torrent.displayTitle;
    switch (provider) {
      case 'debrid':
        {
          final apiKey =
              (await StorageService.getApiKey(canContinue: canContinue)) ?? '';
          checkCurrent();
          final result = await DebridService.addTorrentToDebrid(
            apiKey,
            magnet,
            canContinue: canContinue,
          );
          checkCurrent();
          final playUrl = result['downloadLink'] as String?;
          final linksRaw = (result['links'] as List?) ?? const [];
          final filesRaw = (result['files'] as List?) ?? const [];
          final links = linksRaw.map((e) => e.toString()).toList();
          // RD returns multiple selected files but a single link for an
          // unextracted RAR archive — the provider "open" view isn't useful then.
          final isRar = filesRaw.isNotEmpty
              ? RDFolderTreeBuilder.isRarArchive(
                  filesRaw.map((f) => f as Map<String, dynamic>).toList(),
                  linksRaw,
                )
              : false;
          final rd = RDTorrent(
            id: result['torrentId']?.toString() ?? '',
            filename: title,
            hash: torrent.infohash,
            bytes: torrent.sizeBytes,
            host: '',
            split: 0,
            progress: 100,
            status: 'downloaded',
            added: DateTime.now().toIso8601String(),
            links: links,
          );
          final playlist = await _buildRdPlaylist(
            linksRaw,
            filesRaw,
            apiKey,
            canContinue: canContinue,
          );
          checkCurrent();
          if (playlist != null && playlist.length > 1) {
            var startIndex = playlist.indexWhere((e) => e.url.isNotEmpty);
            if (startIndex < 0) startIndex = 0;
            final start = playlist[startIndex].url.isNotEmpty
                ? playlist[startIndex].url
                : playUrl;
            return AcquiredSource(
              title: title,
              playUrl: start,
              downloadUrls: playUrl != null ? [playUrl] : const [],
              rdFolder: rd,
              playlist: playlist,
              startIndex: startIndex,
              isRarArchive: isRar,
              rdTorrentId: rd.id.isNotEmpty ? rd.id : null,
            );
          }
          return AcquiredSource(
            title: title,
            playUrl: playUrl,
            downloadUrls: playUrl != null ? [playUrl] : const [],
            rdFolder: rd,
            // Single video file: expose its real name so the bound-source
            // episode check can judge it (RAR resolves keep playlist null AND
            // fileName null, staying deliberately lenient).
            fileName: (playlist != null && playlist.length == 1)
                ? playlist.first.title
                : null,
            isRarArchive: isRar,
            rdTorrentId: rd.id.isNotEmpty ? rd.id : null,
            // Raw restricted link so a saved playlist item re-unrestricts later.
            restrictedLink: links.isNotEmpty ? links.first : null,
          );
        }
      case 'torbox':
        {
          final apiKey =
              (await StorageService.getTorboxApiKey(
                canContinue: canContinue,
              )) ??
              '';
          checkCurrent();
          final resp = await TorboxService.createTorrent(
            apiKey: apiKey,
            magnet: magnet,
            addOnlyIfCached: true,
            canContinue: canContinue,
          );
          checkCurrent();
          final ok =
              resp['success'] == true ||
              resp['error'].toString().contains('ALREADY_ADDED');
          if (!ok) {
            if (resp['error'].toString().contains('NOT_CACHED')) {
              throw const TorboxSourceNotCached();
            }
            throw Exception(resp['error']?.toString() ?? 'TorBox add failed');
          }
          final data = resp['data'];
          final torrentId = data is Map
              ? (data['torrent_id'] as num?)?.toInt()
              : null;
          if (torrentId == null) throw Exception('TorBox: no torrent id');
          final tt = await TorboxService.getTorrentById(
            apiKey,
            torrentId,
            canContinue: canContinue,
          );
          checkCurrent();
          final videos = (tt?.files ?? const <TorboxFile>[])
              .where((f) => FileUtils.isVideoFile(f.name))
              .toList();
          if (videos.length <= 1) {
            final file = videos.isNotEmpty
                ? videos.first
                : _pickTorbox(tt?.files ?? const []);
            final playUrl = file == null
                ? null
                : await TorboxService.requestFileDownloadLink(
                    apiKey: apiKey,
                    torrentId: torrentId,
                    fileId: file.id,
                    canContinue: canContinue,
                  );
            checkCurrent();
            return AcquiredSource(
              title: title,
              playUrl: playUrl,
              downloadUrls: playUrl != null ? [playUrl] : const [],
              torboxFolder: tt,
              fileName: file == null ? null : sourceFileName(file.name),
              torboxTorrentId: torrentId,
              // File id so a saved playlist item re-requests a fresh link later.
              torboxFileId: file?.id,
            );
          }
          final (sorted, startIndex) = orderSourceFiles(videos, (f) => f.name);
          final startUrl = await TorboxService.requestFileDownloadLink(
            apiKey: apiKey,
            torrentId: torrentId,
            fileId: sorted[startIndex].id,
            canContinue: canContinue,
          );
          checkCurrent();
          final entries = [
            for (var i = 0; i < sorted.length; i++)
              PlaylistEntry(
                url: i == startIndex ? startUrl : '',
                title: sourceFileName(sorted[i].name),
                provider: 'torbox',
                torboxTorrentId: torrentId,
                torboxFileId: sorted[i].id,
                sizeBytes: sorted[i].size,
                torrentHash: torrent.infohash,
              ),
          ];
          return AcquiredSource(
            title: title,
            playUrl: startUrl,
            downloadUrls: [startUrl],
            torboxFolder: tt,
            playlist: entries,
            startIndex: startIndex,
            torboxTorrentId: torrentId,
          );
        }
      case 'premiumize':
        {
          final apiKey =
              (await StorageService.getPremiumizeApiKey(
                canContinue: canContinue,
              )) ??
              '';
          checkCurrent();
          final cached = await PremiumizeService.isCached(apiKey, magnet);
          checkCurrent();
          if (!cached) {
            throw const PremiumizeSourceNotCached();
          }
          final files = await PremiumizeService.directDownload(apiKey, magnet);
          checkCurrent();
          final videos = files
              .where((f) => FileUtils.isVideoFile(f.path))
              .toList();
          if (videos.length <= 1) {
            final file = videos.isNotEmpty
                ? videos.first
                : _pickPremiumize(files);
            return AcquiredSource(
              title: title,
              playUrl: file?.link,
              downloadUrls: file?.link != null ? [file!.link] : const [],
              fileName: file == null ? null : sourceFileName(file.path),
              // File path so a saved playlist item re-resolves from the cloud.
              premiumizePath: file?.path,
            );
          }
          // Premiumize direct links are all ready — no lazy resolution needed.
          final (sorted, startIndex) = orderSourceFiles(videos, (f) => f.path);
          final entries = [
            for (final f in sorted)
              PlaylistEntry(
                url: f.link,
                title: sourceFileName(f.path),
                provider: 'premiumize',
                premiumizeHash: torrent.infohash,
                premiumizePath: f.path,
                sizeBytes: f.size,
                torrentHash: torrent.infohash,
              ),
          ];
          return AcquiredSource(
            title: title,
            playUrl: sorted[startIndex].link,
            downloadUrls: [sorted[startIndex].link],
            playlist: entries,
            startIndex: startIndex,
          );
        }
      case 'alldebrid':
        {
          final apiKey =
              (await StorageService.getAllDebridApiKey(
                canContinue: canContinue,
              )) ??
              '';
          checkCurrent();
          final result = await AllDebridService.addMagnetAndResolveFiles(
            apiKey,
            magnet,
            canContinue: canContinue,
          );
          checkCurrent();
          final videos = result.files
              .where((f) => FileUtils.isVideoFile(f.path))
              .toList();
          if (videos.length <= 1) {
            final file = videos.isNotEmpty
                ? videos.first
                : _pickAllDebrid(result.files);
            final playUrl = file == null
                ? null
                : await AllDebridService.unlockLink(
                    apiKey,
                    file.link,
                    canContinue: canContinue,
                  );
            checkCurrent();
            return AcquiredSource(
              title: title,
              playUrl: playUrl,
              downloadUrls: playUrl != null ? [playUrl] : const [],
              fileName: file == null ? null : sourceFileName(file.path),
              // Locked link so a saved playlist item re-unlocks a fresh URL.
              allDebridLink: file?.link,
            );
          }
          final (sorted, startIndex) = orderSourceFiles(videos, (f) => f.path);
          final startUrl = await AllDebridService.unlockLink(
            apiKey,
            sorted[startIndex].link,
            canContinue: canContinue,
          );
          checkCurrent();
          final entries = [
            for (var i = 0; i < sorted.length; i++)
              PlaylistEntry(
                url: i == startIndex ? startUrl : '',
                title: sourceFileName(sorted[i].path),
                provider: 'alldebrid',
                allDebridLink: sorted[i].link,
                sizeBytes: sorted[i].size,
                torrentHash: torrent.infohash,
              ),
          ];
          return AcquiredSource(
            title: title,
            playUrl: startUrl,
            downloadUrls: [startUrl],
            playlist: entries,
            startIndex: startIndex,
          );
        }
      case 'pikpak':
        return acquirePikPakSource(magnet, torrent, canContinue: canContinue);
      default:
        throw Exception('Unknown provider: $provider');
    }
  }

  static TorboxFile? _pickTorbox(List<TorboxFile> files) {
    final pool = _videoPool(files, (f) => f.name);
    pool.sort((a, b) => b.size.compareTo(a.size));
    return pool.isEmpty ? null : pool.first;
  }

  static PremiumizeFile? _pickPremiumize(List<PremiumizeFile> files) {
    final pool = _videoPool(files, (f) => f.path);
    pool.sort((a, b) => b.size.compareTo(a.size));
    return pool.isEmpty ? null : pool.first;
  }

  static AllDebridFile? _pickAllDebrid(List<AllDebridFile> files) {
    final pool = _videoPool(files, (f) => f.path);
    pool.sort((a, b) => b.size.compareTo(a.size));
    return pool.isEmpty ? null : pool.first;
  }

  static List<T> _videoPool<T>(List<T> files, String Function(T) nameOf) {
    final videos = files
        .where((f) => FileUtils.isVideoFile(nameOf(f)))
        .toList();
    return videos.isNotEmpty ? videos : List<T>.from(files);
  }

  static Future<List<PlaylistEntry>?> _buildRdPlaylist(
    List<dynamic> links,
    List<dynamic> files,
    String apiKey, {
    bool Function()? canContinue,
  }) async {
    final selectedFiles = files.where((file) => file['selected'] == 1).toList();
    final allFilesToUse = selectedFiles.isNotEmpty ? selectedFiles : files;

    final filesToUse = allFilesToUse.where((file) {
      String? filename =
          file['name']?.toString() ??
          file['filename']?.toString() ??
          file['path']?.toString();
      if (filename != null && filename.startsWith('/')) {
        filename = filename.split('/').last;
      }
      return filename != null && FileUtils.isVideoFile(filename);
    }).toList();

    // Archive check (multiple files but a single link) / no video.
    if (filesToUse.length > 1 && links.length == 1) return null;
    if (filesToUse.isEmpty) return null;

    final filenames = filesToUse.map((file) {
      String? name =
          file['name']?.toString() ??
          file['filename']?.toString() ??
          file['path']?.toString();
      if (name != null && name.startsWith('/')) name = name.split('/').last;
      return name ?? 'Unknown File';
    }).toList();

    final isSeries = SeriesParser.isSeriesPlaylist(filenames);
    final seriesInfos = isSeries ? SeriesParser.parsePlaylist(filenames) : null;

    int firstIndex = 0;
    if (isSeries && seriesInfos != null) {
      int lowestSeason = 999, lowestEpisode = 999;
      for (int i = 0; i < seriesInfos.length; i++) {
        final info = seriesInfos[i];
        if (info.isSeries && info.season != null && info.episode != null) {
          if (info.season! < lowestSeason ||
              (info.season! == lowestSeason && info.episode! < lowestEpisode)) {
            lowestSeason = info.season!;
            lowestEpisode = info.episode!;
            firstIndex = i;
          }
        }
      }
    }

    final entries = <PlaylistEntry>[];
    for (int i = 0; i < filesToUse.length; i++) {
      final file = filesToUse[i];
      String? filename =
          file['name']?.toString() ??
          file['filename']?.toString() ??
          file['path']?.toString();
      String? relativePath = filename;
      if (relativePath != null && relativePath.startsWith('/')) {
        relativePath = relativePath.substring(1);
      }
      if (filename != null && filename.startsWith('/')) {
        filename = filename.split('/').last;
      }
      final finalFilename = filename ?? 'Unknown File';
      final int? sizeBytes = (file is Map) ? (file['bytes'] as int?) : null;
      if (i >= links.length) continue;

      String url = '';
      if (i == firstIndex) {
        try {
          final unrestrictResult = await DebridService.unrestrictLink(
            apiKey,
            links[i],
            canContinue: canContinue,
          );
          url = unrestrictResult['download']?.toString() ?? '';
        } catch (_) {
          url = '';
        }
      }
      entries.add(
        PlaylistEntry(
          url: url,
          title: finalFilename,
          relativePath: relativePath,
          restrictedLink: url.isEmpty ? links[i].toString() : null,
          sizeBytes: sizeBytes,
        ),
      );
    }
    return entries.isEmpty ? null : entries;
  }
}

class TorboxSourceNotCached implements Exception {
  const TorboxSourceNotCached();
}

class PremiumizeSourceNotCached implements Exception {
  const PremiumizeSourceNotCached();
}
