import 'media_server.dart';

/// Server-owned identity. Catalog matching is deliberately not required.
class MediaServerLibraryItem {
  MediaServerLibraryItem.fromJson(Map<String, dynamic> json)
    : data = Map.unmodifiable(json) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const MediaServerException('The server returned an invalid item.');
    }
  }

  final Map<String, dynamic> data;
  String get id => data['Id'] as String? ?? '';
  String get name => data['Name'] as String? ?? 'Untitled';
  String get type => data['Type'] as String? ?? '';
  String get overview => data['Overview'] as String? ?? '';
  int? get year => (data['ProductionYear'] as num?)?.toInt();
  int? get season => (data['ParentIndexNumber'] as num?)?.toInt();
  int? get episode => (data['IndexNumber'] as num?)?.toInt();
  String? get seriesId => data['SeriesId'] as String?;
  String get seriesName => data['SeriesName'] as String? ?? name;
  bool get numberedEpisode =>
      type == 'Episode' &&
      season != null &&
      episode != null &&
      seriesId != null;
  bool get isFolder =>
      data['IsFolder'] == true ||
      const {
        'Series',
        'Season',
        'Folder',
        'CollectionFolder',
        'BoxSet',
        'UserView',
      }.contains(type);
  bool get playable =>
      !isFolder &&
      data['IsMissing'] != true &&
      data['IsPlaceHolder'] != true &&
      const {'Movie', 'Episode', 'Video', 'MusicVideo'}.contains(type);
  bool get watched => (data['UserData'] as Map?)?['Played'] == true;
  double get progress {
    final ticks =
        ((data['UserData'] as Map?)?['PlaybackPositionTicks'] as num?) ?? 0;
    final duration = (data['RunTimeTicks'] as num?) ?? 0;
    return duration > 0 ? (ticks / duration).clamp(0, 1).toDouble() : 0;
  }

  String? get imageId => (data['ImageTags'] as Map?)?['Primary'] != null
      ? id
      : data['SeriesPrimaryImageTag'] != null
      ? seriesId
      : null;
  String get subtitle => [
    if (type == 'Episode') seriesName,
    if (season != null && episode != null) 'S$season · E$episode',
    if (year != null) '$year',
    if (isFolder) type,
  ].join(' · ');

  /// Avoid sharing local progress between unrelated recordings or servers.
  String progressId(String serverIdentity) =>
      'medialibrary:$serverIdentity:${numberedEpisode ? seriesId : id}';
}

class MediaServerLibraryPage {
  const MediaServerLibraryPage(this.items, this.nextOffset);
  final List<MediaServerLibraryItem> items;
  final int? nextOffset;

  factory MediaServerLibraryPage.fromJson(
    Map<String, dynamic> data,
    int offset,
    int limit,
  ) {
    final rows = data['Items'];
    if (rows is! List || rows.any((row) => row is! Map<String, dynamic>)) {
      throw const MediaServerException(
        'The server returned an invalid library response.',
      );
    }
    final total = (data['TotalRecordCount'] as num?)?.toInt();
    return MediaServerLibraryPage(
      rows
          .cast<Map<String, dynamic>>()
          .map(MediaServerLibraryItem.fromJson)
          .toList(),
      rows.isNotEmpty &&
              (total != null
                  ? offset + rows.length < total
                  : rows.length >= limit)
          ? offset + rows.length
          : null,
    );
  }
}
