import '../../models/stremio_addon.dart';
import 'mdblist_models.dart';

enum MdblistDiscoverGroup { library, forYou, discover, lists, catalog }

extension MdblistDiscoverGroupX on MdblistDiscoverGroup {
  String get label => switch (this) {
    MdblistDiscoverGroup.library => 'Library',
    MdblistDiscoverGroup.forYou => 'For You',
    MdblistDiscoverGroup.discover => 'Discover',
    MdblistDiscoverGroup.lists => 'Lists',
    MdblistDiscoverGroup.catalog => 'Catalog',
  };
}

enum MdblistLibraryView {
  continueWatching,
  watchlist,
  history,
  collection,
  ratings,
  dropped,
}

extension MdblistLibraryViewX on MdblistLibraryView {
  String get label => switch (this) {
    MdblistLibraryView.continueWatching => 'Continue Watching',
    MdblistLibraryView.watchlist => 'Watchlist',
    MdblistLibraryView.history => 'History',
    MdblistLibraryView.collection => 'Collection',
    MdblistLibraryView.ratings => 'Ratings',
    MdblistLibraryView.dropped => 'Dropped Shows',
  };
}

enum MdblistListDirectory {
  mine,
  liked,
  external,
  official,
  curated,
  top,
  searchResult,
}

extension MdblistListDirectoryX on MdblistListDirectory {
  String get label => switch (this) {
    MdblistListDirectory.mine => 'My Lists',
    MdblistListDirectory.liked => 'Liked Lists',
    MdblistListDirectory.external => 'External Lists',
    MdblistListDirectory.official => 'Official Lists',
    MdblistListDirectory.curated => 'Curated Lists',
    MdblistListDirectory.top => 'Top Lists',
    MdblistListDirectory.searchResult => 'Search Result',
  };
}

enum MdblistDiscoverChoiceKind {
  recommendation,
  regularList,
  officialList,
  externalList,
}

class MdblistDiscoverChoice {
  final String id;
  final String label;
  final MdblistDiscoverChoiceKind kind;
  final int? numericId;
  final String? slug;
  final String? ownerName;
  final int itemCount;
  final bool liked;
  final int likes;

  const MdblistDiscoverChoice({
    required this.id,
    required this.label,
    required this.kind,
    this.numericId,
    this.slug,
    this.ownerName,
    this.itemCount = 0,
    this.liked = false,
    this.likes = 0,
  });

  String get displayLabel =>
      ownerName == null || ownerName!.isEmpty ? label : '$label · $ownerName';

  @override
  bool operator ==(Object other) =>
      other is MdblistDiscoverChoice && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

class MdblistDiscoverChoices {
  final List<MdblistDiscoverChoice> choices;
  final MdblistResultKind kind;
  final bool fromCache;

  const MdblistDiscoverChoices({
    this.choices = const [],
    this.kind = MdblistResultKind.success,
    this.fromCache = false,
  });

  bool get isUsable =>
      kind == MdblistResultKind.success || kind == MdblistResultKind.partial;
  bool get complete => kind == MdblistResultKind.success;
}

class MdblistCatalogQuota {
  final int? limit;
  final int? used;
  final int? remaining;
  final DateTime? firstExpiresAt;

  const MdblistCatalogQuota({
    this.limit,
    this.used,
    this.remaining,
    this.firstExpiresAt,
  });

  factory MdblistCatalogQuota.fromJson(Map<String, dynamic>? json) =>
      MdblistCatalogQuota(
        limit: _integer(json?['limit']),
        used: _integer(json?['used']),
        remaining: _integer(json?['remaining']),
        firstExpiresAt: mdblistDateTime(json?['first_expires_at']),
      );

  bool get exhausted {
    if (remaining == null || remaining! > 0) return false;
    final expiry = firstExpiresAt;
    return expiry == null || expiry.isAfter(DateTime.now().toUtc());
  }
}

class MdblistCatalogQuery {
  static const _mediaTypes = {'movie', 'show'};
  static const _sorts = {
    'score',
    'imdbpopular',
    'imdbrating',
    'imdbvotes',
    'letterrating',
    'metacritic',
    'rtaudience',
    'rtomatoes',
    'tmdbpopular',
    'released',
    'releasedigital',
    'score_average',
    'title',
  };
  final String mediaType;
  final String? genre;
  final String? country;
  final String? language;
  final int? scoreMin;
  final int? scoreMax;
  final int? yearMin;
  final int? yearMax;
  final String? releasedFrom;
  final String? releasedTo;
  final int? runtimeMin;
  final int? runtimeMax;
  final String sort;
  final String sortOrder;

  const MdblistCatalogQuery({
    this.mediaType = 'movie',
    this.genre,
    this.country,
    this.language,
    this.scoreMin,
    this.scoreMax,
    this.yearMin,
    this.yearMax,
    this.releasedFrom,
    this.releasedTo,
    this.runtimeMin,
    this.runtimeMax,
    this.sort = 'score',
    this.sortOrder = 'desc',
  });

  MdblistCatalogQuery copyWith({
    String? mediaType,
    String? genre,
    String? country,
    String? language,
    int? scoreMin,
    int? scoreMax,
    int? yearMin,
    int? yearMax,
    String? releasedFrom,
    String? releasedTo,
    int? runtimeMin,
    int? runtimeMax,
    String? sort,
    String? sortOrder,
    bool clearGenre = false,
    bool clearCountry = false,
    bool clearLanguage = false,
    bool clearScore = false,
    bool clearYear = false,
    bool clearReleased = false,
    bool clearRuntime = false,
  }) => MdblistCatalogQuery(
    mediaType: mediaType ?? this.mediaType,
    genre: clearGenre ? null : genre ?? this.genre,
    country: clearCountry ? null : country ?? this.country,
    language: clearLanguage ? null : language ?? this.language,
    scoreMin: clearScore ? null : scoreMin ?? this.scoreMin,
    scoreMax: clearScore ? null : scoreMax ?? this.scoreMax,
    yearMin: clearYear ? null : yearMin ?? this.yearMin,
    yearMax: clearYear ? null : yearMax ?? this.yearMax,
    releasedFrom: clearReleased ? null : releasedFrom ?? this.releasedFrom,
    releasedTo: clearReleased ? null : releasedTo ?? this.releasedTo,
    runtimeMin: clearRuntime ? null : runtimeMin ?? this.runtimeMin,
    runtimeMax: clearRuntime ? null : runtimeMax ?? this.runtimeMax,
    sort: sort ?? this.sort,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  String? get validationError {
    if (!_mediaTypes.contains(mediaType)) return 'Choose Movies or Series';
    if (!_sorts.contains(sort) || !const {'asc', 'desc'}.contains(sortOrder)) {
      return 'Choose a valid Catalog sort';
    }
    if ((scoreMin != null && (scoreMin! < 0 || scoreMin! > 100)) ||
        (scoreMax != null && (scoreMax! < 0 || scoreMax! > 100))) {
      return 'Scores must be between 0 and 100';
    }
    if ((runtimeMin != null && runtimeMin! < 0) ||
        (runtimeMax != null && runtimeMax! < 0)) {
      return 'Runtime cannot be negative';
    }
    if (!_validCodes(country) || !_validCodes(language)) {
      return 'Country and language must use up to 10 two-letter codes';
    }
    if ((_clean(releasedFrom) != null && _date(releasedFrom) == null) ||
        (_clean(releasedTo) != null && _date(releasedTo) == null)) {
      return 'Release dates must use a valid YYYY-MM-DD date';
    }
    return null;
  }

  MdblistCatalogQuery get normalized {
    var minimumScore = scoreMin?.clamp(0, 100).toInt();
    var maximumScore = scoreMax?.clamp(0, 100).toInt();
    if (minimumScore != null &&
        maximumScore != null &&
        minimumScore > maximumScore) {
      final swap = minimumScore;
      minimumScore = maximumScore;
      maximumScore = swap;
    }
    var minimumYear = yearMin;
    var maximumYear = yearMax;
    if (minimumYear != null &&
        maximumYear != null &&
        minimumYear > maximumYear) {
      final swap = minimumYear;
      minimumYear = maximumYear;
      maximumYear = swap;
    }
    var minimumDate = _date(releasedFrom);
    var maximumDate = _date(releasedTo);
    if (minimumDate != null &&
        maximumDate != null &&
        minimumDate.compareTo(maximumDate) > 0) {
      final swap = minimumDate;
      minimumDate = maximumDate;
      maximumDate = swap;
    }
    var minimumRuntime = runtimeMin?.clamp(0, 9999);
    var maximumRuntime = runtimeMax?.clamp(0, 9999);
    if (minimumRuntime != null &&
        maximumRuntime != null &&
        minimumRuntime > maximumRuntime) {
      final swap = minimumRuntime;
      minimumRuntime = maximumRuntime;
      maximumRuntime = swap;
    }
    return MdblistCatalogQuery(
      mediaType: _mediaTypes.contains(mediaType) ? mediaType : 'movie',
      genre: _clean(genre),
      country: _clean(country),
      language: _clean(language),
      scoreMin: minimumScore,
      scoreMax: maximumScore,
      yearMin: minimumYear,
      yearMax: maximumYear,
      releasedFrom: minimumDate,
      releasedTo: maximumDate,
      runtimeMin: minimumRuntime,
      runtimeMax: maximumRuntime,
      sort: _sorts.contains(sort) ? sort : 'score',
      sortOrder: sortOrder == 'asc' ? 'asc' : 'desc',
    );
  }

  Map<String, Object?> toQuery({String? cursor, int limit = 100}) {
    final value = normalized;
    return {
      if (value.genre != null) 'genre': value.genre,
      if (value.country != null) 'country': value.country!.toUpperCase(),
      if (value.language != null) 'language': value.language!.toLowerCase(),
      if (value.scoreMin != null) 'score_min': value.scoreMin,
      if (value.scoreMax != null) 'score_max': value.scoreMax,
      if (value.yearMin != null) 'year_min': value.yearMin,
      if (value.yearMax != null) 'year_max': value.yearMax,
      if (value.releasedFrom != null) 'released_from': value.releasedFrom,
      if (value.releasedTo != null) 'released_to': value.releasedTo,
      if (value.runtimeMin != null) 'runtime_min': value.runtimeMin,
      if (value.runtimeMax != null) 'runtime_max': value.runtimeMax,
      'sort': value.sort,
      'sort_order': value.sortOrder,
      'append_to_response': 'poster,ratings,description,genres',
      'limit': limit.clamp(1, 100),
      if (_clean(cursor) != null) 'cursor': _clean(cursor),
    };
  }

  String get cacheKey {
    final entries = toQuery(limit: 100).entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return '${normalized.mediaType}|${entries.map((e) => '${e.key}=${e.value}').join('&')}';
  }

  static String? _clean(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }

  static String? _date(String? value) {
    final cleaned = _clean(value);
    if (cleaned == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(cleaned)) {
      return null;
    }
    final parts = cleaned.split('-');
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    final parsed = DateTime.tryParse(cleaned);
    if (year == null ||
        month == null ||
        day == null ||
        parsed == null ||
        parsed.year != year ||
        parsed.month != month ||
        parsed.day != day) {
      return null;
    }
    return cleaned;
  }

  static bool _validCodes(String? value) {
    final cleaned = _clean(value);
    if (cleaned == null) return true;
    final codes = cleaned.split(',').map((part) => part.trim()).toList();
    return codes.isNotEmpty &&
        codes.length <= 10 &&
        codes.every((code) => RegExp(r'^[A-Za-z]{2}$').hasMatch(code));
  }
}

class MdblistRawPage {
  final List<Map<String, dynamic>> items;
  final String? nextCursor;
  final MdblistCatalogQuota? quota;

  const MdblistRawPage({this.items = const [], this.nextCursor, this.quota});

  bool get exhausted => nextCursor == null || nextCursor!.isEmpty;
}

class MdblistDiscoverPage {
  final List<StremioMeta> items;
  final Map<String, double> progressByImdb;
  final MdblistResultKind kind;
  final String? nextCursor;
  final MdblistCatalogQuota? quota;
  final bool fromCache;

  const MdblistDiscoverPage({
    this.items = const [],
    this.progressByImdb = const {},
    this.kind = MdblistResultKind.success,
    this.nextCursor,
    this.quota,
    this.fromCache = false,
  });

  bool get isUsable =>
      kind == MdblistResultKind.success || kind == MdblistResultKind.partial;
  bool get complete => kind == MdblistResultKind.success;
  bool get exhausted => nextCursor == null || nextCursor!.isEmpty;

  MdblistDiscoverPage copyWith({
    List<StremioMeta>? items,
    Map<String, double>? progressByImdb,
    MdblistResultKind? kind,
    String? nextCursor,
    bool clearCursor = false,
    MdblistCatalogQuota? quota,
    bool? fromCache,
  }) => MdblistDiscoverPage(
    items: items ?? this.items,
    progressByImdb: progressByImdb ?? this.progressByImdb,
    kind: kind ?? this.kind,
    nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
    quota: quota ?? this.quota,
    fromCache: fromCache ?? this.fromCache,
  );
}

int? _integer(Object? value) => value is num
    ? value.toInt()
    : value is String
    ? int.tryParse(value)
    : null;
