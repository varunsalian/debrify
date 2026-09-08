/// Independent presentation categories. Playback and tracking are deliberately
/// outside this policy.
enum MetadataCategory {
  information('Titles and descriptions'),
  posters('Posters'),
  backgrounds('Backdrops and logos'),
  credits('Cast and crew'),
  episodeInformation('Episode descriptions'),
  episodeArtwork('Episode artwork'),
  trailers('Trailers'),
  recommendations('Recommendations');

  const MetadataCategory(this.label);
  final String label;
}

enum MetadataFeature {
  franchises('Franchise collections'),
  people('Actor and director pages'),
  companies('Studio and network browsing'),
  availability('Where to watch'),
  discovery('TMDB discovery');

  const MetadataFeature(this.label);
  final String label;
}

class MetadataPreferences {
  static const current = 'current';
  static const tmdb = 'tmdb';
  static const imdb = 'imdb';
  static const tvmaze = 'tvmaze';
  static const addonPrefix = 'addon:';

  final Map<MetadataCategory, String> providers;
  final Set<MetadataFeature> features;
  final bool fallback;
  final String language;
  final String artworkLanguage;
  final String trailerLanguage;
  final String region;

  MetadataPreferences({
    Map<MetadataCategory, String> providers = const {},
    Set<MetadataFeature> features = const {},
    this.fallback = false,
    this.language = 'en-US',
    this.artworkLanguage = 'same',
    this.trailerLanguage = 'same',
    this.region = 'US',
  }) : providers = Map.unmodifiable({
         for (final entry in providers.entries)
           if (validProvider(entry.value) && supports(entry.key, entry.value))
             entry.key: entry.value,
       }),
       features = Set.unmodifiable(features);

  String provider(MetadataCategory category) => providers[category] ?? current;
  bool get isCurrent =>
      features.isEmpty &&
      MetadataCategory.values.every(
        (category) => provider(category) == current,
      );

  MetadataPreferences copyWith({
    Map<MetadataCategory, String>? providers,
    Set<MetadataFeature>? features,
    bool? fallback,
    String? language,
    String? artworkLanguage,
    String? trailerLanguage,
    String? region,
  }) => MetadataPreferences(
    providers: providers ?? this.providers,
    features: features ?? this.features,
    fallback: fallback ?? this.fallback,
    language: language ?? this.language,
    artworkLanguage: artworkLanguage ?? this.artworkLanguage,
    trailerLanguage: trailerLanguage ?? this.trailerLanguage,
    region: region ?? this.region,
  );

  Map<String, Object> toJson() => {
    'version': 1,
    'providers': {for (final c in MetadataCategory.values) c.name: provider(c)},
    'features': features.map((f) => f.name).toList()..sort(),
    'fallback': fallback,
    'language': language,
    'artworkLanguage': artworkLanguage,
    'trailerLanguage': trailerLanguage,
    'region': region,
  };

  factory MetadataPreferences.fromJson(Map<String, dynamic> json) {
    final raw = json['providers'];
    final flags = json['features'];
    String locale(Object? value, String defaultValue, {bool special = false}) {
      if (value is! String) return defaultValue;
      if (special && (value == 'same' || value == 'original')) return value;
      return RegExp(r'^[a-z]{2,3}(-[A-Z]{2})?$').hasMatch(value)
          ? value
          : defaultValue;
    }

    return MetadataPreferences(
      providers: {
        for (final c in MetadataCategory.values)
          if (raw is Map &&
              raw[c.name] is String &&
              validProvider(raw[c.name] as String) &&
              supports(c, raw[c.name] as String))
            c: raw[c.name] as String,
      },
      features: {
        for (final f in MetadataFeature.values)
          if (flags is List && flags.contains(f.name)) f,
      },
      fallback: json['fallback'] == true,
      language: locale(json['language'], 'en-US'),
      artworkLanguage: locale(json['artworkLanguage'], 'same', special: true),
      trailerLanguage: locale(json['trailerLanguage'], 'same', special: true),
      region:
          json['region'] is String &&
              RegExp(r'^[A-Z]{2}$').hasMatch(json['region'] as String)
          ? json['region'] as String
          : 'US',
    );
  }

  static bool supports(MetadataCategory category, String provider) {
    if (provider == current || provider == tmdb) return true;
    if (provider == imdb) return category == MetadataCategory.credits;
    if (provider == tvmaze) return category == MetadataCategory.episodeArtwork;
    return provider.startsWith(addonPrefix) &&
        category != MetadataCategory.credits &&
        category != MetadataCategory.recommendations;
  }

  static bool validProvider(String value) =>
      const {current, tmdb, imdb, tvmaze}.contains(value) ||
      RegExp(r'^addon:[a-f0-9]{64}$').hasMatch(value);
}
