/// A file or folder in a PikPak drive.
///
/// Replaces the `Map<String, dynamic>` every PikPak call used to hand back and
/// that 56 call sites indexed by string key. Two things that cost real bugs are
/// settled here once: `size` arrives from PikPak as a *string*, so every reader
/// had to remember `int.tryParse(x['size'].toString())` — one of them didn't
/// and wrote `x['size'] as int?` — and the streaming URL lives in one of two
/// unrelated places depending on the file.
class PikPakFile {
  final String id;
  final String name;
  final PikPakKind kind;
  final String mimeType;

  /// Bytes. PikPak sends this as a string; 0 when absent or unparseable.
  final int size;

  final PikPakPhase phase;

  /// 0–100 while an offline download is filling this entry in; 0 once it is
  /// complete or was never a download.
  final int progress;

  /// Direct download link. Present on files PikPak has finished processing.
  final String? webContentLink;

  /// The folder this lives in. Empty string at the drive root.
  final String parentId;

  final String? parentName;
  final DateTime? createdTime;

  /// Transcoded renditions, best first once [streamingUrl] has picked.
  final List<PikPakMedia> medias;

  /// Entries this one groups. Non-empty only for
  /// [PikPakKind.virtualSeason] — a grouping the browser builds client-side so
  /// a season pack reads as folders. PikPak has no such kind.
  final List<PikPakFile> children;

  /// Path from the root of a recursive scan, e.g. `Season 1/Episode 1.mkv`.
  /// Set by [PikPakApiService.listFilesRecursive] when it was asked to track
  /// paths; null otherwise. PikPak itself does not send this.
  final String? fullPath;

  const PikPakFile({
    required this.id,
    required this.name,
    required this.kind,
    required this.mimeType,
    required this.size,
    required this.phase,
    this.progress = 0,
    this.webContentLink,
    this.parentId = '',
    this.parentName,
    this.createdTime,
    this.medias = const [],
    this.children = const [],
    this.fullPath,
  });

  /// A client-side folder standing in for one season of a pack.
  factory PikPakFile.seasonGroup({
    required int season,
    required List<PikPakFile> files,
  }) => PikPakFile(
    id: 'virtual_season_$season',
    name: season == 0 ? 'Season 0 - Specials' : 'Season $season',
    kind: PikPakKind.virtualSeason,
    mimeType: '',
    size: files.fold(0, (sum, f) => sum + f.size),
    phase: PikPakPhase.complete,
    children: files,
  );

  bool get isVirtual => kind == PikPakKind.virtualSeason;

  /// The same file, tagged with where a recursive scan found it.
  PikPakFile at(String path) => PikPakFile(
    id: id,
    name: name,
    kind: kind,
    mimeType: mimeType,
    size: size,
    phase: phase,
    progress: progress,
    webContentLink: webContentLink,
    parentId: parentId,
    parentName: parentName,
    createdTime: createdTime,
    medias: medias,
    children: children,
    fullPath: path,
  );

  /// What to show and what to name a download: the scan path when there is
  /// one, the bare name otherwise.
  String get displayPath => fullPath ?? name;

  bool get isFolder => kind == PikPakKind.folder;
  bool get isFile => kind == PikPakKind.file;
  bool get isVideo => mimeType.toLowerCase().startsWith('video/');
  bool get isReady => phase == PikPakPhase.complete;
  bool get hasFailed => phase == PikPakPhase.error;

  /// Something a player can open, or null when PikPak has given us neither.
  ///
  /// Prefers a transcoded media link — the default rendition, then the original
  /// — because those stream; [webContentLink] is a download URL and only works
  /// as a fallback.
  String? get streamingUrl {
    if (medias.isNotEmpty) {
      final chosen = medias.firstWhere(
        (m) => m.isDefault,
        orElse: () =>
            medias.firstWhere((m) => m.isOrigin, orElse: () => medias.first),
      );
      final url = chosen.url;
      if (url != null && url.isNotEmpty) return url;
    }
    final web = webContentLink;
    return (web != null && web.isNotEmpty) ? web : null;
  }

  static PikPakFile fromJson(Map json) {
    // createFolder and some drive endpoints wrap the entry in `file`.
    final map = json['file'] is Map ? json['file'] as Map : json;
    return PikPakFile(
      id: '${map['id'] ?? ''}',
      name: '${map['name'] ?? ''}',
      kind: PikPakKind.parse(map['kind']),
      mimeType: '${map['mime_type'] ?? ''}',
      size: int.tryParse('${map['size'] ?? ''}') ?? 0,
      phase: PikPakPhase.parse(map['phase']),
      progress: int.tryParse('${map['progress'] ?? ''}') ?? 0,
      webContentLink: _text(map['web_content_link']),
      parentId: '${map['parent_id'] ?? ''}',
      parentName: _text(map['parent_name']),
      createdTime: DateTime.tryParse('${map['created_time'] ?? ''}'),
      medias: switch (map['medias']) {
        final List raw => raw.whereType<Map>().map(PikPakMedia.fromJson).toList(),
        _ => const [],
      },
    );
  }

  /// PikPak's list endpoints wrap the array in `files`. An entry that is not
  /// an object is dropped rather than thrown on: one malformed element must
  /// not cost the whole listing.
  static List<PikPakFile> listFromJson(Object? json) => switch (json) {
    final List raw => _each(raw),
    final Map map => switch (map['files']) {
      final List raw => _each(raw),
      _ => const [],
    },
    _ => const [],
  };

  static List<PikPakFile> _each(List raw) =>
      raw.whereType<Map>().map(PikPakFile.fromJson).toList();

  static String? _text(Object? value) {
    final text = value?.toString();
    return (text == null || text.isEmpty) ? null : text;
  }
}

/// One transcoded rendition of a video file.
class PikPakMedia {
  final bool isDefault;
  final bool isOrigin;
  final String? url;

  const PikPakMedia({
    required this.isDefault,
    required this.isOrigin,
    this.url,
  });

  static PikPakMedia fromJson(Map json) {
    final link = json['link'];
    return PikPakMedia(
      isDefault: json['is_default'] == true,
      isOrigin: json['is_origin'] == true,
      url: link is Map ? PikPakFile._text(link['url']) : null,
    );
  }
}

/// PikPak's `kind` discriminator.
enum PikPakKind {
  file,
  folder,

  /// A client-side season grouping. Never comes off the wire.
  virtualSeason,

  /// A kind PikPak added after this was written.
  unknown;

  static PikPakKind parse(Object? raw) => switch ('$raw') {
    'drive#file' => PikPakKind.file,
    'drive#folder' => PikPakKind.folder,
    _ => PikPakKind.unknown,
  };
}

/// Where an offline download has got to. PikPak spells these `PHASE_TYPE_*`.
enum PikPakPhase {
  pending,
  running,
  complete,
  error,

  /// Absent, or a phase PikPak added after this was written.
  unknown;

  static PikPakPhase parse(Object? raw) => switch ('$raw') {
    'PHASE_TYPE_PENDING' => PikPakPhase.pending,
    'PHASE_TYPE_RUNNING' => PikPakPhase.running,
    'PHASE_TYPE_COMPLETE' => PikPakPhase.complete,
    'PHASE_TYPE_ERROR' => PikPakPhase.error,
    _ => PikPakPhase.unknown,
  };
}
