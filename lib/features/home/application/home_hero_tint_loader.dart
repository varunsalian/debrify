import 'dart:async';
import 'dart:ui' show Color;
import '../../../models/stremio_addon.dart';

typedef HomeHeroTintResolver = Future<Color?> Function(String poster);

/// One view's delayed tint requests and title cache. Displayed color and ordered
/// publication to the shell remain caller-owned; the shared image cache is borrowed.
class HomeHeroTintLoader {
  HomeHeroTintLoader({
    required HomeHeroTintResolver resolve,
    required bool Function() isOwnerCurrent,
  }) : _resolve = resolve,
       _isOwnerCurrent = isOwnerCurrent;

  final HomeHeroTintResolver _resolve;
  final bool Function() _isOwnerCurrent;
  final Map<String, Color?> _cache = {};
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;
  bool get _active => !_disposed && _isOwnerCurrent();

  void load(
    StremioMeta item, {
    required bool Function() isCurrent,
    required void Function(Color?) publish,
  }) {
    if (!_active) return;
    _timer?.cancel();
    final generation = ++_generation;
    bool current() => _active && isCurrent() && generation == _generation;
    // Cache hits and missing posters also wait for focus rest. Synchronous
    // publication here would repaint the board on every cached-title keypress.
    _timer = Timer(const Duration(milliseconds: 120), () async {
      _timer = null;
      if (!current()) return;
      final poster = item.poster;
      if (poster == null || poster.isEmpty) {
        publish(null);
        return;
      }
      if (_cache.containsKey(item.id)) {
        publish(_cache[item.id]);
        return;
      }
      // The shared resolver converts extraction errors into cached nulls.
      final color = await _resolve(poster);
      if (!current()) return;
      // Preserve the original threshold: up to 301 entries, then a full clear.
      if (_cache.length > 300) _cache.clear();
      _cache[item.id] = color;
      publish(color);
    });
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _timer = null;
    _cache.clear();
  }
}
