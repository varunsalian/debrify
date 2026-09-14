import 'package:flutter/foundation.dart';

import '../skip_segment_service.dart';

typedef SkipSegmentRequest = ({
  String imdbId,
  int season,
  int episode,
  Duration duration,
  String key,
});

/// Owns provider, pending request key, generation and session fetch cache.
/// Published segments and their key remain owned by the player host.
class SkipSegmentSession {
  SkipSegmentSession({
    required SkipSegmentRequest? Function() currentRequest,
    required bool Function() isMounted,
    required String? Function() loadedKey,
    required void Function(SkipSegments, String) publish,
  }) : _currentRequest = currentRequest,
       _isMounted = isMounted,
       _loadedKey = loadedKey,
       _publish = publish;

  final SkipSegmentRequest? Function() _currentRequest;
  final bool Function() _isMounted;
  final String? Function() _loadedKey;
  final void Function(SkipSegments, String) _publish;

  SkipSegmentProvider? _skipSegmentProvider;
  String? _loadingSkipSegmentsKey;
  int _skipSegmentsFetchGeneration = 0;
  final Map<String, SkipSegments> _skipSegmentsCache = <String, SkipSegments>{};

  void configure(bool enabled, String providerId) {
    _skipSegmentProvider?.close();
    _skipSegmentProvider = enabled
        ? SkipSegmentProviders.create(providerId)
        : null;
  }

  void sync() {
    final request = _currentRequest();
    final provider = _skipSegmentProvider;
    if (request == null || provider == null) return;
    if (_loadedKey() == request.key || _loadingSkipSegmentsKey == request.key) {
      return;
    }

    if (_skipSegmentsCache.containsKey(request.key)) {
      final cached = _skipSegmentsCache[request.key]!;
      if (_isMounted()) {
        _publish(cached, request.key);
      }
      return;
    }

    final generation = ++_skipSegmentsFetchGeneration;
    _loadingSkipSegmentsKey = request.key;
    provider
        .fetch(
          imdbId: request.imdbId,
          season: request.season,
          episode: request.episode,
          duration: request.duration,
        )
        .then((segments) {
          _skipSegmentsCache[request.key] = segments;
          if (!_isMounted() || generation != _skipSegmentsFetchGeneration) {
            return;
          }
          if (_currentRequest()?.key != request.key) return;
          _publish(segments, request.key);
        })
        .catchError((Object error) {
          // Missing skip data must never affect playback. Cache the miss for
          // this session so an offline API cannot be retried on every position
          // tick.
          _skipSegmentsCache[request.key] = SkipSegments.empty;
          debugPrint(
            'SkipSegments: ${provider.displayName} fetch failed: $error',
          );
          if (!_isMounted() || generation != _skipSegmentsFetchGeneration) {
            return;
          }
          if (_currentRequest()?.key != request.key) return;
          _publish(SkipSegments.empty, request.key);
        })
        .whenComplete(() {
          if (_loadingSkipSegmentsKey == request.key) {
            _loadingSkipSegmentsKey = null;
          }
        });
  }

  void reset() {
    _skipSegmentsFetchGeneration++;
    _loadingSkipSegmentsKey = null;
  }

  void close() {
    _skipSegmentsFetchGeneration++;
    _skipSegmentProvider?.close();
    _skipSegmentProvider = null;
  }
}
