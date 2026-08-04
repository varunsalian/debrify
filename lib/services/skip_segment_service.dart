import 'dart:async';
import 'dart:convert';

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
  final SkipSegment? intro;
  final SkipSegment? outro;

  const SkipSegments({this.intro, this.outro});

  static const empty = SkipSegments();

  SkipSegment? segmentAt(Duration position) {
    if (intro?.contains(position) == true) return intro;
    if (outro?.contains(position) == true) return outro;
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
  static const skipDb = 'skipdb';
  static const labels = <String, String>{skipDb: 'SkipDB'};

  static bool supports(String id) => labels.containsKey(id);

  static SkipSegmentProvider create(String id, {http.Client? client}) {
    switch (id) {
      case skipDb:
        return SkipDbSegmentProvider(client: client);
      default:
        return SkipDbSegmentProvider(client: client);
    }
  }
}

class SkipDbSegmentProvider implements SkipSegmentProvider {
  static final Uri _defaultEndpoint = Uri.parse(
    'https://api.skipdb.tv/api/segments',
  );

  final http.Client _client;
  final bool _ownsClient;
  final Uri _endpoint;
  final Duration _timeout;

  SkipDbSegmentProvider({
    http.Client? client,
    Uri? endpoint,
    Duration timeout = const Duration(seconds: 6),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _endpoint = endpoint ?? _defaultEndpoint,
       _timeout = timeout;

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
    final uri = _endpoint.replace(
      queryParameters: <String, String>{
        'imdb_id': imdbId,
        'season': '$season',
        'episode': '$episode',
        if (duration > Duration.zero) 'duration': '${duration.inSeconds}',
      },
    );

    final response = await _client
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(_timeout);
    if (response.statusCode != 200) return SkipSegments.empty;

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return SkipSegments.empty;
    final segments = decoded['segments'];
    if (segments is! Map) return SkipSegments.empty;

    return SkipSegments(
      intro: _parseSegment(segments['intro'], SkipSegmentType.intro),
      outro: _parseSegment(segments['outro'], SkipSegmentType.outro),
    );
  }

  SkipSegment? _parseSegment(Object? value, SkipSegmentType type) {
    if (value is! Map) return null;

    // SkipDB explicitly marks large duration mismatches as uncertain. A
    // manual skip should never jump on a timestamp the provider itself says
    // does not fit the current release.
    final match = value['match']?.toString();
    if (match == 'out-of-range') return null;

    final startMs = _asInt(value['start_ms']);
    final endMs = _asInt(value['end_ms']);
    if (startMs == null || endMs == null || startMs < 0 || endMs <= startMs) {
      return null;
    }

    return SkipSegment(
      type: type,
      start: Duration(milliseconds: startMs),
      end: Duration(milliseconds: endMs),
      confidence: _asDouble(value['confidence']),
      match: match,
    );
  }

  int? _asInt(Object? value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
