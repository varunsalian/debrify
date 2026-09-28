import '../../../models/playlist_entry.dart';
import '../../../models/torrent.dart';
import '../../../services/pikpak_api_service.dart';
import '../../../utils/file_utils.dart';
import '../../../utils/series_parser.dart';
import '../models/acquired_source.dart';
import '../models/pikpak_prepared_source.dart';
import 'pikpak_source_preparation.dart';
import 'source_file_ordering.dart';

Future<AcquiredSource> acquirePikPakSource(
  String magnet,
  Torrent torrent, {
  bool Function()? canContinue,
}) async {
  final title = torrent.displayTitle;
  final pikpak = PikPakApiService.instance;
  final prepared = await preparePikPakSource(
    magnet: magnet,
    addDownload: pikpak.addOfflineDownload,
    readTask: pikpak.getTaskStatus,
    readFile: pikpak.getFileDetails,
    listFolder: (id) async => (await pikpak.listFiles(parentId: id)).files,
    canContinue: canContinue,
  );
  if (canContinue?.call() == false) throw const PikPakSourceRetired();

  final playlist = await buildPikPakSourcePlaylist(
    torrent.name,
    prepared.videos,
    pikpak,
    canContinue: canContinue,
  );
  if (canContinue?.call() == false) throw const PikPakSourceRetired();
  if (playlist == null || playlist.isEmpty) {
    throw Exception('PikPak: could not resolve a playable stream.');
  }
  var startIndex = playlist.indexWhere((e) => e.url.isNotEmpty);
  if (startIndex < 0) startIndex = 0;
  final capturedFileId = prepared.fileId;
  return AcquiredSource(
    title: title,
    playUrl: playlist[startIndex].url,
    downloadUrls: playlist[startIndex].url.isNotEmpty
        ? [playlist[startIndex].url]
        : const [],
    playlist: playlist.length > 1 ? playlist : null,
    startIndex: startIndex,
    // Single video file: expose its real name so the bound-source episode
    // check can judge it instead of passing vacuously.
    fileName: playlist.length == 1 ? playlist.first.title : null,
    pikpakFileId: capturedFileId,
    // The playable video-file id (folder id is capturedFileId) so a single
    // saved to a playlist re-resolves its stream instead of failing on the
    // folder.
    pikpakVideoFileId: playlist.length == 1
        ? playlist.first.pikpakFileId
        : null,
  );
}

Future<List<PlaylistEntry>?> buildPikPakSourcePlaylist(
  String torrentName,
  List<PikPakSourceVideo> videoFiles,
  PikPakApiService pikpak, {
  bool Function()? canContinue,
}) async {
  if (canContinue?.call() == false) return null;
  if (videoFiles.isEmpty) return null;
  if (videoFiles.length == 1) {
    final file = videoFiles.first;
    try {
      final fullData = await pikpak.getFileDetails(file.id.toString());
      if (canContinue?.call() == false) return null;
      final url = pikpak.getStreamingUrl(fullData);
      if (url == null) return null;
      return [
        PlaylistEntry(
          url: url,
          title: file.name ?? torrentName,
          relativePath: file.relativePath,
          provider: 'pikpak',
          pikpakFileId: file.id,
          sizeBytes: file.sizeBytes ?? 0,
        ),
      ];
    } catch (_) {
      return null;
    }
  }

  final items = <_PikPakItem>[
    for (final file in videoFiles)
      _PikPakItem(
        file: file,
        seriesInfo: SeriesParser.parseFilename(_pikpakDisplayName(file)),
        displayName: _pikpakDisplayName(file),
      ),
  ];
  final fnames = items.map((e) => e.displayName).toList();
  final isSeriesCollection =
      items.length > 1 && SeriesParser.isSeriesPlaylist(fnames);

  final sorted = [...items];
  if (isSeriesCollection) {
    sorted.sort((a, b) {
      final sc = (a.seriesInfo.season ?? 0).compareTo(b.seriesInfo.season ?? 0);
      if (sc != 0) return sc;
      final ec = (a.seriesInfo.episode ?? 0).compareTo(
        b.seriesInfo.episode ?? 0,
      );
      if (ec != 0) return ec;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
  } else {
    sorted.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
  }

  final seriesInfos = sorted.map((e) => e.seriesInfo).toList();
  var startIndex = isSeriesCollection
      ? firstSourceEpisodeIndex(seriesInfos)
      : 0;
  if (startIndex < 0 || startIndex >= sorted.length) startIndex = 0;

  String initialUrl = '';
  try {
    final fullData = await pikpak.getFileDetails(
      sorted[startIndex].file.id.toString(),
    );
    if (canContinue?.call() == false) return null;
    initialUrl = pikpak.getStreamingUrl(fullData) ?? '';
  } catch (_) {
    return null;
  }
  if (initialUrl.isEmpty) return null;

  final entries = <PlaylistEntry>[];
  for (var i = 0; i < sorted.length; i++) {
    final entry = sorted[i];
    final episodeLabel = _formatPikPakTitle(
      info: entry.seriesInfo,
      fallback: entry.displayName,
      isSeriesCollection: isSeriesCollection,
    );
    final combinedTitle = _combineTitle(
      seriesTitle: entry.seriesInfo.title,
      episodeLabel: episodeLabel,
      isSeriesCollection: isSeriesCollection,
      fallback: entry.displayName,
    );
    entries.add(
      PlaylistEntry(
        url: i == startIndex ? initialUrl : '',
        title: combinedTitle,
        relativePath: entry.file.relativePath,
        provider: 'pikpak',
        pikpakFileId: entry.file.id,
        sizeBytes: entry.file.sizeBytes,
      ),
    );
  }
  return entries.isEmpty ? null : entries;
}

String _pikpakDisplayName(PikPakSourceVideo file) {
  final name = file.name ?? '';
  if (name.isNotEmpty) return FileUtils.getFileName(name);
  return 'File ${file.id}';
}

String _formatPikPakTitle({
  required SeriesInfo info,
  required String fallback,
  required bool isSeriesCollection,
}) {
  if (!isSeriesCollection) return fallback;
  final season = info.season;
  final episode = info.episode;
  if (info.isSeries && season != null && episode != null) {
    final s = season.toString().padLeft(2, '0');
    final e = episode.toString().padLeft(2, '0');
    final desc = info.episodeTitle?.trim().isNotEmpty == true
        ? info.episodeTitle!.trim()
        : (info.title?.trim().isNotEmpty == true
              ? info.title!.trim()
              : fallback);
    return 'S${s}E$e · $desc';
  }
  return fallback;
}

String _combineTitle({
  required String? seriesTitle,
  required String episodeLabel,
  required bool isSeriesCollection,
  required String fallback,
}) {
  if (!isSeriesCollection) return fallback;
  final clean = seriesTitle?.replaceAll(RegExp(r'[._\-]+$'), '').trim();
  if (clean != null && clean.isNotEmpty) return '$clean $episodeLabel';
  return fallback;
}

class _PikPakItem {
  final PikPakSourceVideo file;
  final SeriesInfo seriesInfo;
  final String displayName;
  const _PikPakItem({
    required this.file,
    required this.seriesInfo,
    required this.displayName,
  });
}
