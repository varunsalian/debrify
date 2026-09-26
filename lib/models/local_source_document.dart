import 'series_source.dart';

/// Document URIs stay opaque: display names are used only for episode parsing.
class LocalSourceDocument {
  const LocalSourceDocument({
    required this.uri,
    required this.name,
    required this.relativePath,
    required this.isDirectory,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  factory LocalSourceDocument.fromMap(Map<dynamic, dynamic> map) =>
      LocalSourceDocument(
        uri: map['uri'] as String,
        name: map['name'] as String,
        relativePath: map['relativePath'] as String,
        isDirectory: map['isDirectory'] == true,
        sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
        modifiedAt: (map['modifiedAt'] as num?)?.toInt() ?? 0,
      );

  final String uri;
  final String name;
  final String relativePath;
  final bool isDirectory;
  final int sizeBytes;
  final int modifiedAt;

  SeriesSource toSource() => SeriesSource(
    torrentHash: SeriesSource.localSourceHash(uri),
    torrentName: name,
    debridService: SeriesSource.localService,
    debridTorrentId: uri,
    boundAt: DateTime.now().millisecondsSinceEpoch,
    localUri: uri,
    localKind: isDirectory
        ? SeriesSource.localKindSeriesFolder
        : SeriesSource.localKindMovieFile,
    localSizeBytes: sizeBytes,
    localModifiedAt: modifiedAt,
  );
}
