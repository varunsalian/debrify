// Immutable views of the tracker's REST (proto-JSON) payloads.
//
// The server writes proto defaults rather than omitting fields, so an absent
// value can arrive as "", "0", 0 or null. The parsers below normalise all of
// those to null, so callers never mistake "tmdb: 0" for a real id.

enum LedgerMediaKind {
  movie('MEDIA_KIND_MOVIE'),
  show('MEDIA_KIND_SHOW'),
  season('MEDIA_KIND_SEASON'),
  episode('MEDIA_KIND_EPISODE');

  const LedgerMediaKind(this.wire);
  final String wire;

  static LedgerMediaKind? parse(Object? value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }
}

/// External ids. Only non-empty, non-zero values survive parsing.
class LedgerIds {
  const LedgerIds({this.imdb, this.tmdb, this.tvdb});

  final String? imdb;
  final String? tmdb;
  final String? tvdb;

  bool get isEmpty => imdb == null && tmdb == null && tvdb == null;

  factory LedgerIds.fromJson(Object? json) {
    if (json is! Map) return const LedgerIds();
    return LedgerIds(
      imdb: _imdb(json['imdb']),
      tmdb: _positiveId(json['tmdb']),
      tvdb: _positiveId(json['tvdb']),
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    if (imdb != null) 'imdb': imdb!,
    if (tmdb != null) 'tmdb': tmdb!,
    if (tvdb != null) 'tvdb': tvdb!,
  };

  static final RegExp _imdbPattern = RegExp(r'^tt[0-9]{1,12}$');

  static String? _imdb(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return _imdbPattern.hasMatch(trimmed) ? trimmed : null;
  }

  static String? _positiveId(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    final parsed = int.tryParse(text);
    return parsed == null || parsed <= 0 ? null : '$parsed';
  }
}

/// A movie, show, season or episode as the catalog describes it. Episodes
/// and seasons carry their [show].
class LedgerMedia {
  const LedgerMedia({
    required this.kind,
    this.id,
    this.name,
    this.slug,
    this.year,
    this.image,
    this.ids = const LedgerIds(),
    this.runtimeMinutes,
    this.show,
    this.season,
    this.number,
    this.aired,
    this.status,
  });

  final LedgerMediaKind kind;
  final String? id;
  final String? name;
  final String? slug;
  final int? year;
  final String? image;
  final LedgerIds ids;
  final int? runtimeMinutes;
  final LedgerMedia? show;
  final int? season;
  final int? number;
  final String? aired;
  final String? status;

  /// The IMDb id of the title this item belongs to: the movie's own, or the
  /// show's for a season or episode.
  String? get titleImdbId => switch (kind) {
    LedgerMediaKind.movie || LedgerMediaKind.show => ids.imdb,
    LedgerMediaKind.season || LedgerMediaKind.episode => show?.ids.imdb,
  };

  static LedgerMedia? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = LedgerMediaKind.parse(json['kind']);
    if (kind == null) return null;
    return LedgerMedia(
      kind: kind,
      id: ledgerString(json['id']),
      name: ledgerString(json['name']),
      slug: ledgerString(json['slug']),
      year: ledgerPositiveInt(json['year']),
      image: ledgerString(json['image']),
      ids: LedgerIds.fromJson(json['ids']),
      runtimeMinutes: ledgerPositiveInt(json['runtime']),
      show: fromJson(json['show']),
      season: ledgerNonNegativeInt(json['season']),
      number: ledgerPositiveInt(json['number']),
      aired: ledgerString(json['aired']),
      status: ledgerString(json['status']),
    );
  }
}

/// Names an item for a write. The server resolves any one of the ids, or an
/// episode by its show's ids plus season and number (Stremio `tt…:S:E` form).
class LedgerMediaRef {
  const LedgerMediaRef._({
    required this.kind,
    this.ids = const LedgerIds(),
    this.showIds = const LedgerIds(),
    this.season,
    this.number,
  });

  final LedgerMediaKind kind;
  final LedgerIds ids;
  final LedgerIds showIds;
  final int? season;
  final int? number;

  factory LedgerMediaRef.movie(String imdbId) => LedgerMediaRef._(
    kind: LedgerMediaKind.movie,
    ids: LedgerIds(imdb: _imdb(imdbId)),
  );

  factory LedgerMediaRef.show(String imdbId) => LedgerMediaRef._(
    kind: LedgerMediaKind.show,
    ids: LedgerIds(imdb: _imdb(imdbId)),
  );

  factory LedgerMediaRef.season(String showImdbId, int season) =>
      LedgerMediaRef._(
        kind: LedgerMediaKind.season,
        showIds: LedgerIds(imdb: _imdb(showImdbId)),
        season: season,
      );

  factory LedgerMediaRef.episode(String showImdbId, int season, int episode) =>
      LedgerMediaRef._(
        kind: LedgerMediaKind.episode,
        showIds: LedgerIds(imdb: _imdb(showImdbId)),
        season: season,
        number: episode,
      );

  /// IMDb ids are sent trimmed and lower-case, the form the server validates.
  static String _imdb(String id) => id.trim().toLowerCase();

  Map<String, Object> toJson() => <String, Object>{
    'kind': kind.wire,
    if (!ids.isEmpty) 'ids': ids.toJson(),
    if (!showIds.isEmpty) 'showIds': showIds.toJson(),
    if (season != null) 'season': season!,
    if (number != null) 'number': number!,
  };
}

String? ledgerString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? ledgerPositiveInt(Object? value) {
  final parsed = ledgerNonNegativeInt(value);
  return parsed == null || parsed == 0 ? null : parsed;
}

int? ledgerNonNegativeInt(Object? value) {
  final parsed = switch (value) {
    int() => value,
    num() => value.toInt(),
    String() => int.tryParse(value.trim()),
    _ => null,
  };
  return parsed == null || parsed < 0 ? null : parsed;
}

/// Proto floats may arrive as numbers or as "NaN"/"Infinity" strings.
double? ledgerPercent(Object? value) {
  final parsed = switch (value) {
    num() => value.toDouble(),
    String() => double.tryParse(value),
    _ => null,
  };
  if (parsed == null || !parsed.isFinite) return null;
  return parsed.clamp(0.0, 100.0).toDouble();
}

DateTime? ledgerTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}
