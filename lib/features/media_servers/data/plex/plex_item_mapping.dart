/// Pure mapping from Plex Media Server JSON to the media-server maps the
/// shared service and library models read.
///
/// Temporary exception (docs/media-servers.md): the legacy
/// Jellyfin/Emby client returns Jellyfin-shaped maps, so Plex produces the
/// same keys. Only the keys listed here are read by consumers:
/// - item: `Id`, `Name`, `Type`, `ProductionYear`, `ParentIndexNumber`,
///   `IndexNumber`, `SeriesId`, `SeriesName`, `Overview`, `IsFolder`,
///   `RunTimeTicks`, `UserData {Played, PlaybackPositionTicks,
///   LastPlayedDate}`, `ImageTags {Primary}`, `SeriesPrimaryImageTag`,
///   `CollectionType`;
/// - media source: `Id`, `Container`, `Size`, `MediaStreams[] {Type, Codec,
///   Width, Height, Language, IsExternal, ColorTransfer, VideoRange,
///   DvProfile}`.
///
/// Server file paths (`Part.file`) are never copied.
library;

const _ticksPerMs = 10000;

final _numericId = RegExp(r'^[0-9]{1,18}$');
final _containerName = RegExp(r'^[a-z0-9]{1,8}$');

/// A Plex `ratingKey`, section key or part id, which are always digits.
String? plexNumericId(Object? value) {
  final text = value is int ? '$value' : value;
  return text is String && _numericId.hasMatch(text) ? text : null;
}

const _types = {
  'movie': 'Movie',
  'show': 'Series',
  'season': 'Season',
  'episode': 'Episode',
  'clip': 'Video',
};

const _collectionTypes = {
  'movie': 'movies',
  'show': 'tvshows',
  'artist': 'music',
  'photo': 'photos',
};

int? _int(Object? value) =>
    value is num && value.isFinite && value >= 0 ? value.toInt() : null;

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

/// A library section (`/library/sections` `Directory`) as a library view row.
/// Its id is prefixed with `s` so it never collides with a `ratingKey`.
Map<String, dynamic>? plexSectionItem(Map<String, dynamic> section) {
  final key = plexNumericId(section['key']);
  if (key == null) return null;
  return {
    'Id': 's$key',
    'Name': _text(section['title']) ?? 'Library',
    'Type': 'CollectionFolder',
    'IsFolder': true,
    if (_collectionTypes[section['type']] case final collection?)
      'CollectionType': collection,
  };
}

/// A Plex `Metadata` entry as a media-server item, or null when it has no
/// usable id or an unsupported type.
Map<String, dynamic>? plexItem(Map<String, dynamic> metadata) {
  final id = plexNumericId(metadata['ratingKey']);
  final type = _types[metadata['type']];
  if (id == null || type == null) return null;
  final duration = _int(metadata['duration']);
  final offset = _int(metadata['viewOffset']) ?? 0;
  final lastViewed = _int(metadata['lastViewedAt']);
  final item = <String, dynamic>{
    'Id': id,
    'Name': _text(metadata['title']) ?? 'Untitled',
    'Type': type,
    'IsFolder': type == 'Series' || type == 'Season',
    'UserData': {
      'Played': (_int(metadata['viewCount']) ?? 0) > 0,
      'PlaybackPositionTicks': offset * _ticksPerMs,
      if (lastViewed != null)
        'LastPlayedDate': DateTime.fromMillisecondsSinceEpoch(
          lastViewed * 1000,
          isUtc: true,
        ).toIso8601String(),
    },
  };
  if (_int(metadata['year']) case final year?) item['ProductionYear'] = year;
  if (_text(metadata['summary']) case final summary?) {
    item['Overview'] = summary;
  }
  if (duration != null && duration > 0) {
    item['RunTimeTicks'] = duration * _ticksPerMs;
  }
  if (_text(metadata['thumb']) != null) {
    item['ImageTags'] = {'Primary': 'thumb'};
  }
  if (type == 'Episode') {
    if (_int(metadata['parentIndex']) case final season?) {
      item['ParentIndexNumber'] = season;
    }
    if (_int(metadata['index']) case final episode?) {
      item['IndexNumber'] = episode;
    }
    if (plexNumericId(metadata['grandparentRatingKey']) case final show?) {
      item['SeriesId'] = show;
    }
    if (_text(metadata['grandparentTitle']) case final show?) {
      item['SeriesName'] = show;
    }
    if (_text(metadata['grandparentThumb']) != null) {
      item['SeriesPrimaryImageTag'] = 'thumb';
    }
  } else if (type == 'Season') {
    if (_int(metadata['index']) case final season?) {
      item['IndexNumber'] = season;
    }
    if (plexNumericId(metadata['parentRatingKey']) case final show?) {
      item['SeriesId'] = show;
    }
    if (_text(metadata['parentTitle']) case final show?) {
      item['SeriesName'] = show;
    }
  }
  return item;
}

/// The single file of a Plex `Media` entry as a direct-play media source, or
/// null when it cannot be played as one original file: several parts
/// (stacked), a missing or inaccessible file, or invalid identifiers.
Map<String, dynamic>? plexMediaSource(Map<String, dynamic> media) {
  final parts = media['Part'];
  if (parts is! List || parts.length != 1 || parts.single is! Map) {
    return null;
  }
  final part = (parts.single as Map).cast<String, dynamic>();
  final partId = plexNumericId(part['id']);
  final named = (_text(part['container']) ?? _text(media['container']))
      ?.toLowerCase();
  // Not yet analysed: Plex ignores the URL's file extension, so play it as
  // plain `file` rather than skipping it.
  final container = named != null && _containerName.hasMatch(named)
      ? named
      : null;
  if (partId == null ||
      (named != null && container == null) ||
      part['exists'] == false ||
      part['accessible'] == false) {
    return null;
  }
  final streams = <Map<String, dynamic>>[];
  for (final stream in (part['Stream'] as List? ?? const []).whereType<Map>()) {
    switch (stream['streamType']) {
      case 1:
        streams.add({
          'Type': 'Video',
          if (_text(stream['codec']) case final codec?) 'Codec': codec,
          if (_int(stream['width']) case final width?) 'Width': width,
          if (_int(stream['height']) case final height?) 'Height': height,
          if (_text(stream['colorTrc']) case final transfer?)
            'ColorTransfer': transfer,
          if (stream['DOVIPresent'] == true) 'VideoRange': 'DOVI',
          if (_int(stream['DOVIProfile']) case final profile?)
            'DvProfile': profile,
        });
      case 2:
        streams.add({
          'Type': 'Audio',
          'IsExternal': false,
          if (_text(stream['languageCode']) case final language?)
            'Language': language,
        });
    }
  }
  if (!streams.any((stream) => stream['Type'] == 'Video')) {
    // List responses omit streams; the media entry still has the frame size.
    streams.insert(0, {
      'Type': 'Video',
      if (_text(media['videoCodec']) case final codec?) 'Codec': codec,
      if (_int(media['width']) case final width?) 'Width': width,
      if (_int(media['height']) case final height?) 'Height': height,
    });
  }
  return {
    'Id': '${partId}_${container ?? 'file'}',
    'Container': ?container,
    'Size': _int(part['size']) ?? 0,
    'MediaStreams': streams,
  };
}

/// Splits a media-source id from [plexMediaSource] back into its part id and
/// container, or null if it was not produced by it.
({String partId, String container})? plexPartFromSourceId(String sourceId) {
  final split = sourceId.indexOf('_');
  if (split <= 0) return null;
  final partId = sourceId.substring(0, split);
  final container = sourceId.substring(split + 1);
  if (!_numericId.hasMatch(partId) || !_containerName.hasMatch(container)) {
    return null;
  }
  return (partId: partId, container: container);
}

/// The external ids attached to a Plex item: `Guid[]` entries for modern
/// agents and the item `guid` for legacy agents, as `provider:value`
/// (`imdb:tt…`, `tmdb:N`, `tvdb:N`).
Set<String> plexExternalIds(Map<String, dynamic> metadata) {
  final ids = <String>{};
  void add(String provider, String value) {
    if (provider == 'imdb' && RegExp(r'^tt\d+$').hasMatch(value) ||
        provider != 'imdb' && RegExp(r'^\d+$').hasMatch(value)) {
      ids.add('$provider:$value');
    }
  }

  for (final guid in (metadata['Guid'] as List? ?? const []).whereType<Map>()) {
    final match = RegExp(
      r'^(imdb|tmdb|tvdb)://([^/?#]+)$',
    ).firstMatch('${guid['id']}');
    if (match != null) add(match[1]!, match[2]!);
  }
  final legacy = RegExp(
    r'^com\.plexapp\.agents\.(imdb|themoviedb|thetvdb)://([^/?#]+)',
  ).firstMatch('${metadata['guid']}');
  if (legacy != null) {
    add(switch (legacy[1]) {
      'imdb' => 'imdb',
      'themoviedb' => 'tmdb',
      _ => 'tvdb',
    }, legacy[2]!);
  }
  return ids;
}
