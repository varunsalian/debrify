import 'dart:async';
import '../../../models/stremio_addon.dart';
import '../../../services/youtube_service.dart' show YoutubeResolvedStreams;
import '../models/home_hero_trailer_resolution.dart';

/// One view's ambient trailer request lifetime. The caller owns suppression,
/// eligibility and displayed signals; this owner keeps timing and retirement.
class HomeHeroTrailerLoader {
  HomeHeroTrailerLoader({
    required Future<HomeHeroTrailerResolution> Function(
      StremioMeta item,
      bool Function() current,
    )
    resolve,
    required bool Function() Function() captureScopeGuard,
  }) : _resolve = resolve,
       _captureScopeGuard = captureScopeGuard;

  final Future<HomeHeroTrailerResolution> Function(
    StremioMeta item,
    bool Function() current,
  )
  _resolve;
  final bool Function() Function() _captureScopeGuard;
  Timer? _dwell;
  Timer? _failsafe;
  int _generation = 0;
  bool _disposed = false;

  bool _active(int generation, bool Function() isCurrent) =>
      !_disposed && isCurrent() && generation == _generation;

  void schedule(
    StremioMeta item, {
    required Duration delay,
    required bool Function() isCurrent,
    required void Function() reset,
    required bool Function() begin,
    required void Function(YoutubeResolvedStreams) publish,
    required void Function() fail,
  }) {
    if (_disposed) return;
    _dwell?.cancel();
    final generation = ++_generation;
    final scopeCurrent = _captureScopeGuard();
    bool current() => _active(generation, isCurrent) && scopeCurrent();
    // Old failsafes are already inert after generation retirement; release
    // their timers as well so the per-view owner retains at most one of each.
    _failsafe?.cancel();
    reset();
    // A synchronous signal listener may retire/restart the request during reset.
    if (!_active(generation, isCurrent)) return;
    _dwell = Timer(delay, () async {
      if (!current()) return;
      if (!begin()) return;
      void guardedFailure() {
        // Preserve the original failure guard: request/mount, without scope.
        if (_active(generation, isCurrent)) fail();
      }

      try {
        final resolution = await _resolve(item, current);
        if (resolution.retired) return;
        final streams = resolution.streams;
        if (streams == null) return guardedFailure();
        if (!current()) return;
        publish(streams);
        // Publication can synchronously retire this request too.
        if (!_active(generation, isCurrent)) return;
        _failsafe = Timer(const Duration(seconds: 15), guardedFailure);
      } catch (_) {
        guardedFailure();
      }
    });
  }

  void cancel() {
    _dwell?.cancel();
    _generation++;
    _failsafe?.cancel();
  }

  void dispose() {
    _disposed = true;
    _dwell?.cancel();
    _failsafe?.cancel();
  }
}
