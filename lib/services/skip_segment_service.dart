import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum SkipSegmentType { intro, outro }

class SkipSegment {
  final SkipSegmentType type;
  final Duration start;
  final Duration end;
  final double? confidence;
  final String? match;

  const SkipSegment({
    required this.type,
    required this.start,
    required this.end,
    this.confidence,
    this.match,
  });

  bool contains(Duration position) => position >= start && position < end;
}

class SkipSegments {
  final List<SkipSegment> intros;
  final List<SkipSegment> outros;

  const SkipSegments({this.intros = const [], this.outros = const []});

  static const empty = SkipSegments();

  SkipSegment? get intro => intros.isEmpty ? null : intros.first;
  SkipSegment? get outro => outros.isEmpty ? null : outros.first;

  SkipSegment? segmentAt(Duration position) {
    for (final segment in intros) {
      if (segment.contains(position)) return segment;
    }
    for (final segment in outros) {
      if (segment.contains(position)) return segment;
    }
    return null;
  }
}

abstract class SkipSegmentProvider {
  String get id;
  String get displayName;

  Future<SkipSegments> fetch({
    required String imdbId,
    required int season,
    required int episode,
    required Duration duration,
  });

  void close();
}

abstract final class SkipSegmentProviders {
  static const auto = 'auto';
  static const skipDb = 'skipdb';
  static const introDb = 'introdb';
  static const theIntroDb = 'theintrodb';
  static const labels = <String, String>{
    auto: 'Auto (Recommended)',
    skipDb: 'SkipDB',
    introDb: 'IntroDB',
    theIntroDb: 'TheIntroDB',
  };

  static bool supports(String id) => labels.containsKey(id);

  /// IntroDB currently permits browser requests only from introdb.app. Keep it
  /// selectable on native platforms, where CORS does not apply, while avoiding
  /// a provider choice that cannot work in the Flutter web player.
  static bool isAvailable(String id) {
    return supports(id) && !(kIsWeb && id == introDb);
  }

  static Map<String, String> get availableLabels => <String, String>{
    for (final entry in labels.entries)
      if (isAvailable(entry.key)) entry.key: entry.value,
  };

  static SkipSegmentProvider create(String id, {http.Client? client}) {
    switch (id) {
      case auto:
        return AutoSkipSegmentProvider(client: client);
      case skipDb:
        return SkipDbSegmentProvider(client: client);
      case introDb:
        return IntroDbSegmentProvider(client: client);
      case theIntroDb:
        return TheIntroDbSegmentProvider(client: client);
      default:
        return AutoSkipSegmentProvider(client: client);
    }
  }
}

class AutoSkipSegmentProvider implements SkipSegmentProvider {
  static const Duration _defaultTimeout = Duration(seconds: 3);

  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;
  late final List<SkipSegmentProvider> _providers;

  AutoSkipSegmentProvider({
    http.Client? client,
    Duration timeout = _defaultTimeout,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _timeout = timeout {
    _providers = <SkipSegmentProvider>[
      SkipDbSegmentProvider(client: _client),
      TheIntroDbSegmentProvider(client: _client),
      if (!kIsWeb) IntroDbSegmentProvider(client: _client),
    ];
  }

  @override
  String get id => SkipSegmentProviders.auto;

  @override
  String get displayName => 'Auto';

  @override
  Future<SkipSegments> fetch({
    required String imdbId,
    required int season,
    required int episode,
    required Duration duration,
  }) async {
    final results = <String, SkipSegments>{};
    final requests = _providers.map((provider) async {
      try {
        results[provider.id] = await provider.fetch(
          imdbId: imdbId,
          season: season,
          episode: episode,
          duration: duration,
        );
      } catch (error) {
        debugPrint(
          'SkipSegments: ${provider.displayName} fetch failed: $error',
        );
      }
    });

    try {
      await Future.wait(requests).timeout(_timeout);
    } on TimeoutException {
      // Use whichever providers completed within the shared deadline. Each
      // request catches its own late error, so unfinished work cannot surface
      // as an unhandled exception after this result has been returned.
    }

    List<SkipSegment> intros = const [];
    List<SkipSegment> outros = const [];
    for (final provider in _providers) {
      final candidate = results[provider.id];
      if (candidate == null) continue;
      if (intros.isEmpty && candidate.intros.isNotEmpty) {
        intros = candidate.intros;
      }
      if (outros.isEmpty && candidate.outros.isNotEmpty) {
        outros = candidate.outros;
      }
      if (intros.isNotEmpty && outros.isNotEmpty) break;
    }
    return SkipSegments(intros: intros, outros: outros);
  }

  @override
  void close() {
    for (final provider in _providers) {
      provider.close();
    }
    if (_ownsClient) _client.close();
  }
}

abstract class _HttpSkipSegmentProvider implements SkipSegmentProvider {
  final http.Client _client;
  final bool _ownsClient;
  final Uri _endpoint;
  final Duration _timeout;

  _HttpSkipSegmentProvider({
    required Uri endpoint,
    http.Client? client,
    Duration timeout = const Duration(seconds: 6),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _endpoint = endpoint,
       _timeout = timeout;

  Future<http.Response> get(Map<String, String> queryParameters) {
    final uri = _endpoint.replace(queryParameters: queryParameters);
    return _client
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(_timeout);
  }

  Map<Object?, Object?>? decodeObject(http.Response response) {
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    return decoded is Map ? decoded : null;
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}

class SkipDbSegmentProvider extends _HttpSkipSegmentProvider {
  static final Uri _defaultEndpoint = Uri.parse(
    'https://api.skipdb.tv/api/segments',
  );

  SkipDbSegmentProvider({
    super.client,
    Uri? endpoint,
    super.timeout = const Duration(seconds: 6),
  }) : super(endpoint: endpoint ?? _defaultEndpoint);

  @override
  String get id => SkipSegmentProviders.skipDb;

  @override
  String get displayName => 'SkipDB';

  @override
  Future<SkipSegments> fetch({
    required String imdbId,
    required int season,
    required int episode,
    required Duration duration,
  }) async {
    final response = await get(<String, String>{
      'imdb_id': imdbId,
      'season': '$season',
      'episode': '$episode',
      if (duration > Duration.zero) 'duration': '${duration.inSeconds}',
    });
    final decoded = decodeObject(response);
    if (decoded == null) return SkipSegments.empty;
    final segments = decoded['segments'];
    if (segments is! Map) return SkipSegments.empty;

    final intro = _parseSegment(
      segments['intro'],
      SkipSegmentType.intro,
      duration,
    );
    final outro = _parseSegment(
      segments['outro'],
      SkipSegmentType.outro,
      duration,
    );
    return SkipSegments(
      intros: _normalizeSegments(<SkipSegment?>[intro]),
      outros: _normalizeSegments(<SkipSegment?>[outro]),
    );
  }

  SkipSegment? _parseSegment(
    Object? value,
    SkipSegmentType type,
    Duration duration,
  ) {
    if (value is! Map) return null;

    // SkipDB explicitly marks large duration mismatches as uncertain. A
    // manual skip should never jump on a timestamp the provider itself says
    // does not fit the current release.
    final match = value['match']?.toString();
    if (match == 'out-of-range') return null;

    return _parseBoundedSegment(
      value: value,
      type: type,
      duration: duration,
      match: match,
      confidence: _asDouble(value['confidence']),
    );
  }
}

class IntroDbSegmentProvider extends _HttpSkipSegmentProvider {
  static final Uri _defaultEndpoint = Uri.parse(
    'https://api.introdb.app/segments',
  );

  IntroDbSegmentProvider({
    super.client,
    Uri? endpoint,
    super.timeout = const Duration(seconds: 6),
  }) : super(endpoint: endpoint ?? _defaultEndpoint);

  @override
  String get id => SkipSegmentProviders.introDb;

  @override
  String get displayName => 'IntroDB';

  @override
  Future<SkipSegments> fetch({
    required String imdbId,
    required int season,
    required int episode,
    required Duration duration,
  }) async {
    final response = await get(<String, String>{
      'imdb_id': imdbId,
      'season': '$season',
      'episode': '$episode',
    });
    final decoded = decodeObject(response);
    if (decoded == null) return SkipSegments.empty;

    final intro = _parseBoundedSegment(
      value: decoded['intro'],
      type: SkipSegmentType.intro,
      duration: duration,
      confidence: _confidenceFrom(decoded['intro']),
    );
    final outro = _parseBoundedSegment(
      value: decoded['outro'],
      type: SkipSegmentType.outro,
      duration: duration,
      confidence: _confidenceFrom(decoded['outro']),
    );
    return SkipSegments(
      intros: _normalizeSegments(<SkipSegment?>[intro]),
      outros: _normalizeSegments(<SkipSegment?>[outro]),
    );
  }

  double? _confidenceFrom(Object? value) {
    return value is Map ? _asDouble(value['confidence']) : null;
  }
}

class TheIntroDbSegmentProvider extends _HttpSkipSegmentProvider {
  static final Uri _defaultEndpoint = Uri.parse(
    'https://api.theintrodb.org/v3/media',
  );

  TheIntroDbSegmentProvider({
    super.client,
    Uri? endpoint,
    super.timeout = const Duration(seconds: 6),
  }) : super(endpoint: endpoint ?? _defaultEndpoint);

  @override
  String get id => SkipSegmentProviders.theIntroDb;

  @override
  String get displayName => 'TheIntroDB';

  @override
  Future<SkipSegments> fetch({
    required String imdbId,
    required int season,
    required int episode,
    required Duration duration,
  }) async {
    final response = await get(<String, String>{
      'imdb_id': imdbId,
      'season': '$season',
      'episode': '$episode',
      if (duration > Duration.zero) 'duration_ms': '${duration.inMilliseconds}',
    });
    final decoded = decodeObject(response);
    if (decoded == null) return SkipSegments.empty;

    return SkipSegments(
      intros: _parseSegmentArray(
        decoded['intro'],
        SkipSegmentType.intro,
        duration,
        nullStartAtBeginning: true,
      ),
      outros: _parseSegmentArray(
        decoded['credits'],
        SkipSegmentType.outro,
        duration,
        nullEndAtMediaEnd: true,
      ),
    );
  }

  List<SkipSegment> _parseSegmentArray(
    Object? value,
    SkipSegmentType type,
    Duration duration, {
    bool nullStartAtBeginning = false,
    bool nullEndAtMediaEnd = false,
  }) {
    if (value is! List) return const [];
    return _normalizeSegments(
      value.map(
        (entry) => _parseBoundedSegment(
          value: entry,
          type: type,
          duration: duration,
          nullStartAtBeginning: nullStartAtBeginning,
          nullEndAtMediaEnd: nullEndAtMediaEnd,
        ),
      ),
    );
  }
}

/// The earliest point a credits marker is believable, as a fraction of the
/// episode's runtime.
///
/// The providers do sometimes return an outro that sits in the middle of the
/// episode — far enough in that "Skip credits" was appearing halfway through a
/// watch. Nothing downstream can tell a bad timestamp from a good one, and
/// acting on one throws the viewer past a chunk of the episode they had not
/// seen, so a marker that cannot be the credits is dropped at the door rather
/// than offered and distrusted.
///
/// Inclusive: a marker at exactly this fraction is kept — `d * 0.9` rounds back
/// onto the integer 90% mark for every duration an episode can report, so the
/// boundary is exact despite 0.9 being unrepresentable.
///
/// Must stay in step with `MIN_OUTRO_START_FRACTION` in
/// android/app/src/main/kotlin/com/debrify/app/tv/SkipDbSegmentClient.kt, which
/// gates the native TV player. The two read the same providers and must not
/// disagree about the same episode.
const double _minOutroStartFraction = 0.9;

SkipSegment? _parseBoundedSegment({
  required Object? value,
  required SkipSegmentType type,
  required Duration duration,
  bool nullStartAtBeginning = false,
  bool nullEndAtMediaEnd = false,
  double? confidence,
  String? match,
}) {
  if (value is! Map || duration <= Duration.zero) return null;
  if (!value.containsKey('start_ms') || !value.containsKey('end_ms')) {
    return null;
  }

  final startMs = value['start_ms'] == null && nullStartAtBeginning
      ? 0
      : _asInt(value['start_ms']);
  final endMs = value['end_ms'] == null && nullEndAtMediaEnd
      ? duration.inMilliseconds
      : _asInt(value['end_ms']);
  final durationMs = duration.inMilliseconds;
  if (startMs == null ||
      endMs == null ||
      startMs < 0 ||
      endMs <= startMs ||
      startMs >= durationMs ||
      endMs > durationMs) {
    return null;
  }

  // Intros are deliberately not gated: they legitimately begin anywhere in the
  // opening minutes, and a cold open can push one surprisingly late.
  if (type == SkipSegmentType.outro &&
      startMs < durationMs * _minOutroStartFraction) {
    return null;
  }

  return SkipSegment(
    type: type,
    start: Duration(milliseconds: startMs),
    end: Duration(milliseconds: endMs),
    confidence: confidence,
    match: match,
  );
}

List<SkipSegment> _normalizeSegments(Iterable<SkipSegment?> values) {
  final sorted = values.whereType<SkipSegment>().toList()
    ..sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.end.compareTo(b.end);
    });
  final result = <SkipSegment>[];
  for (final segment in sorted) {
    final duplicate = result.any(
      (existing) =>
          existing.type == segment.type &&
          existing.start == segment.start &&
          existing.end == segment.end,
    );
    if (!duplicate) result.add(segment);
  }
  return List<SkipSegment>.unmodifiable(result);
}

int? _asInt(Object? value) {
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '');
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}
