/// User-selectable Quick Play behavior.
///
/// The `debrifyDefault` factories below are the compatibility contract for
/// the pre-profile Quick Play flow. Keep those values in sync with the legacy
/// fallbacks in StorageService when the old behavior intentionally changes.
enum QuickPlayPreset {
  debrifyDefault,
  addonOrder,
  bestQuality,
  fastest,
  custom,
}

enum QuickPlaySourceMode {
  torrentsThenAddons,
  addonsThenTorrents,
  together,
  torrentsOnly,
  addonsOnly,
}

enum QuickPlayRanking { debrify, exactOrder, quality, smallest, readyFirst }

enum QuickPlayPackPreference { widestFirst, seasonFirst, exactEpisodeOnly }

bool _listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final name = raw?.toString();
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

class QuickPlayRules {
  final QuickPlayPreset preset;
  final QuickPlaySourceMode sourceMode;
  final QuickPlayRanking ranking;
  final bool useFilters;
  final bool relaxFilters;
  final bool tryNextOnFailure;
  final int maxAttempts;
  final bool allowDirectLinks;
  final bool validateDirectLinks;
  final bool preferSeriesPacks;
  final QuickPlayPackPreference packPreference;

  /// The shipped series pack search asks engines and addons together. This is
  /// kept independently from [sourceMode] so changing an unrelated setting
  /// does not silently change that legacy route. Choosing Source order in the
  /// new UI turns this off and makes [sourceMode] authoritative for packs too.
  final bool preserveLegacyCombinedPackSearch;

  /// Zero preserves the legacy behavior: wait for the engine search to
  /// complete. A positive value is an opt-in overall engine timeout.
  final int searchTimeoutSeconds;

  /// Fifteen seconds is StremioService's legacy per-addon default.
  final int addonTimeoutSeconds;

  /// How long a successful-but-empty pack search is suppressed for a season.
  final int failedPackCacheHours;

  /// User-arranged provider order for this tab — normalized keys
  /// ('engine:<id>' / 'stremio:<name>'), see SourcePriority. EMPTY means the
  /// user never customized it: ordering everywhere keeps the shipped behavior
  /// (mixed seeders-relevance), which is why this must never default to a
  /// materialized list.
  final List<String> sourcePriority;

  const QuickPlayRules({
    required this.preset,
    required this.sourceMode,
    required this.ranking,
    required this.useFilters,
    required this.relaxFilters,
    required this.tryNextOnFailure,
    required this.maxAttempts,
    required this.allowDirectLinks,
    required this.validateDirectLinks,
    required this.preferSeriesPacks,
    required this.packPreference,
    required this.preserveLegacyCombinedPackSearch,
    required this.searchTimeoutSeconds,
    required this.addonTimeoutSeconds,
    required this.failedPackCacheHours,
    this.sourcePriority = const [],
  });

  factory QuickPlayRules.debrifyDefault({required bool isMovie}) =>
      QuickPlayRules(
        preset: QuickPlayPreset.debrifyDefault,
        sourceMode: QuickPlaySourceMode.torrentsThenAddons,
        ranking: QuickPlayRanking.debrify,
        useFilters: true,
        relaxFilters: true,
        tryNextOnFailure: true,
        maxAttempts: 5,
        allowDirectLinks: true,
        validateDirectLinks: true,
        preferSeriesPacks: !isMovie,
        packPreference: QuickPlayPackPreference.widestFirst,
        preserveLegacyCombinedPackSearch: !isMovie,
        searchTimeoutSeconds: 0,
        addonTimeoutSeconds: 15,
        failedPackCacheHours: 6,
        sourcePriority: const [],
      );

  factory QuickPlayRules.forPreset(
    QuickPlayPreset preset, {
    required bool isMovie,
  }) {
    final base = QuickPlayRules.debrifyDefault(isMovie: isMovie);
    switch (preset) {
      case QuickPlayPreset.debrifyDefault:
        return base;
      case QuickPlayPreset.addonOrder:
        return base.copyWith(
          preset: preset,
          sourceMode: QuickPlaySourceMode.addonsThenTorrents,
          ranking: QuickPlayRanking.exactOrder,
          useFilters: false,
          relaxFilters: false,
          preferSeriesPacks: false,
          preserveLegacyCombinedPackSearch: false,
        );
      case QuickPlayPreset.bestQuality:
        return base.copyWith(
          preset: preset,
          sourceMode: QuickPlaySourceMode.together,
          ranking: QuickPlayRanking.quality,
          preserveLegacyCombinedPackSearch: false,
        );
      case QuickPlayPreset.fastest:
        return base.copyWith(
          preset: preset,
          sourceMode: QuickPlaySourceMode.together,
          ranking: QuickPlayRanking.readyFirst,
          useFilters: false,
          relaxFilters: false,
          preferSeriesPacks: false,
          preserveLegacyCombinedPackSearch: false,
          searchTimeoutSeconds: 5,
          addonTimeoutSeconds: 10,
        );
      case QuickPlayPreset.custom:
        return base.copyWith(preset: QuickPlayPreset.custom);
    }
  }

  bool matchesDebrifyDefault({required bool isMovie}) =>
      this == QuickPlayRules.debrifyDefault(isMovie: isMovie);

  QuickPlayRules copyWith({
    QuickPlayPreset? preset,
    QuickPlaySourceMode? sourceMode,
    QuickPlayRanking? ranking,
    bool? useFilters,
    bool? relaxFilters,
    bool? tryNextOnFailure,
    int? maxAttempts,
    bool? allowDirectLinks,
    bool? validateDirectLinks,
    bool? preferSeriesPacks,
    QuickPlayPackPreference? packPreference,
    bool? preserveLegacyCombinedPackSearch,
    int? searchTimeoutSeconds,
    int? addonTimeoutSeconds,
    int? failedPackCacheHours,
    List<String>? sourcePriority,
  }) => QuickPlayRules(
    preset: preset ?? this.preset,
    sourceMode: sourceMode ?? this.sourceMode,
    ranking: ranking ?? this.ranking,
    useFilters: useFilters ?? this.useFilters,
    relaxFilters: relaxFilters ?? this.relaxFilters,
    tryNextOnFailure: tryNextOnFailure ?? this.tryNextOnFailure,
    maxAttempts: (maxAttempts ?? this.maxAttempts).clamp(1, 10).toInt(),
    allowDirectLinks: allowDirectLinks ?? this.allowDirectLinks,
    validateDirectLinks: validateDirectLinks ?? this.validateDirectLinks,
    preferSeriesPacks: preferSeriesPacks ?? this.preferSeriesPacks,
    packPreference: packPreference ?? this.packPreference,
    preserveLegacyCombinedPackSearch:
        preserveLegacyCombinedPackSearch ??
        this.preserveLegacyCombinedPackSearch,
    searchTimeoutSeconds: (searchTimeoutSeconds ?? this.searchTimeoutSeconds)
        .clamp(0, 60)
        .toInt(),
    addonTimeoutSeconds: (addonTimeoutSeconds ?? this.addonTimeoutSeconds)
        .clamp(5, 120)
        .toInt(),
    failedPackCacheHours: (failedPackCacheHours ?? this.failedPackCacheHours)
        .clamp(0, 168)
        .toInt(),
    sourcePriority: sourcePriority ?? this.sourcePriority,
  );

  Map<String, dynamic> toJson() => {
    'preset': preset.name,
    'sourceMode': sourceMode.name,
    'ranking': ranking.name,
    'useFilters': useFilters,
    'relaxFilters': relaxFilters,
    'tryNextOnFailure': tryNextOnFailure,
    'maxAttempts': maxAttempts,
    'allowDirectLinks': allowDirectLinks,
    'validateDirectLinks': validateDirectLinks,
    'preferSeriesPacks': preferSeriesPacks,
    'packPreference': packPreference.name,
    'preserveLegacyCombinedPackSearch': preserveLegacyCombinedPackSearch,
    'searchTimeoutSeconds': searchTimeoutSeconds,
    'addonTimeoutSeconds': addonTimeoutSeconds,
    'failedPackCacheHours': failedPackCacheHours,
    if (sourcePriority.isNotEmpty) 'sourcePriority': sourcePriority,
  };

  factory QuickPlayRules.fromJson(
    Map<String, dynamic> json, {
    required bool isMovie,
  }) {
    final fallback = QuickPlayRules.debrifyDefault(isMovie: isMovie);
    int integer(String key, int fallbackValue) =>
        (json[key] as num?)?.round() ?? fallbackValue;
    bool boolean(String key, bool fallbackValue) =>
        json[key] is bool ? json[key] as bool : fallbackValue;
    final preset = _enumValue(
      QuickPlayPreset.values,
      json['preset'],
      fallback.preset,
    );
    final sourceMode = _enumValue(
      QuickPlaySourceMode.values,
      json['sourceMode'],
      fallback.sourceMode,
    );
    // Profiles saved by the first v2 implementation predate the explicit
    // pack-search compatibility bit. Named non-default presets and custom
    // source modes were intended to honor their selected source priority;
    // Debrify/default-shaped custom profiles retain the shipped combined pack
    // route when upgraded.
    final inferredLegacyPackSearch =
        !isMovie &&
        (preset == QuickPlayPreset.debrifyDefault ||
            (preset == QuickPlayPreset.custom &&
                sourceMode == QuickPlaySourceMode.torrentsThenAddons));
    return QuickPlayRules(
      preset: preset,
      sourceMode: sourceMode,
      ranking: _enumValue(
        QuickPlayRanking.values,
        json['ranking'],
        fallback.ranking,
      ),
      useFilters: boolean('useFilters', fallback.useFilters),
      relaxFilters: boolean('relaxFilters', fallback.relaxFilters),
      tryNextOnFailure: boolean('tryNextOnFailure', fallback.tryNextOnFailure),
      maxAttempts: integer(
        'maxAttempts',
        fallback.maxAttempts,
      ).clamp(1, 10).toInt(),
      allowDirectLinks: boolean('allowDirectLinks', fallback.allowDirectLinks),
      validateDirectLinks: boolean(
        'validateDirectLinks',
        fallback.validateDirectLinks,
      ),
      preferSeriesPacks:
          !isMovie && boolean('preferSeriesPacks', fallback.preferSeriesPacks),
      packPreference: _enumValue(
        QuickPlayPackPreference.values,
        json['packPreference'],
        fallback.packPreference,
      ),
      preserveLegacyCombinedPackSearch:
          !isMovie &&
          boolean('preserveLegacyCombinedPackSearch', inferredLegacyPackSearch),
      searchTimeoutSeconds: integer(
        'searchTimeoutSeconds',
        fallback.searchTimeoutSeconds,
      ).clamp(0, 60).toInt(),
      addonTimeoutSeconds: integer(
        'addonTimeoutSeconds',
        fallback.addonTimeoutSeconds,
      ).clamp(5, 120).toInt(),
      failedPackCacheHours: integer(
        'failedPackCacheHours',
        fallback.failedPackCacheHours,
      ).clamp(0, 168).toInt(),
      sourcePriority:
          (json['sourcePriority'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is QuickPlayRules &&
      preset == other.preset &&
      sourceMode == other.sourceMode &&
      ranking == other.ranking &&
      useFilters == other.useFilters &&
      relaxFilters == other.relaxFilters &&
      tryNextOnFailure == other.tryNextOnFailure &&
      maxAttempts == other.maxAttempts &&
      allowDirectLinks == other.allowDirectLinks &&
      validateDirectLinks == other.validateDirectLinks &&
      preferSeriesPacks == other.preferSeriesPacks &&
      packPreference == other.packPreference &&
      preserveLegacyCombinedPackSearch ==
          other.preserveLegacyCombinedPackSearch &&
      searchTimeoutSeconds == other.searchTimeoutSeconds &&
      addonTimeoutSeconds == other.addonTimeoutSeconds &&
      failedPackCacheHours == other.failedPackCacheHours &&
      _listEquals(sourcePriority, other.sourcePriority);

  @override
  int get hashCode => Object.hash(
    preset,
    sourceMode,
    ranking,
    useFilters,
    relaxFilters,
    tryNextOnFailure,
    maxAttempts,
    allowDirectLinks,
    validateDirectLinks,
    preferSeriesPacks,
    packPreference,
    preserveLegacyCombinedPackSearch,
    searchTimeoutSeconds,
    addonTimeoutSeconds,
    failedPackCacheHours,
    Object.hashAll(sourcePriority),
  );
}
